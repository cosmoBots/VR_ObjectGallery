extends RefCounted
class_name SimpleMqttClient

signal connected
signal disconnected
signal message(topic: String, payload: String)
signal log_event(message: String)

const STATUS_NONE := -1
const STATUS_CONNECTING := 0
const STATUS_CONNECTED := 1
const STATUS_DISCONNECTED := 2

var host: String = ""
var port: int = 1883
var username: String = ""
var password: String = ""
var client_id: String = "godot"
var keepalive_seconds: int = 30

var _peer := StreamPeerTCP.new()
var _status: int = STATUS_NONE
var _packet_id: int = 1
var _rx_buffer := PackedByteArray()
var _subscriptions: Array[String] = []
var _last_io_msec: int = 0
var _sent_connect: bool = false
var _last_disconnect_reason: String = ""
var _tcp_open_logged: bool = false
var _pending_subscriptions: Dictionary = {}


func configure(config: Dictionary) -> void:
	host = str(config.get("host", "")).strip_edges()
	port = int(config.get("port", 1883))
	username = str(config.get("username", ""))
	password = str(config.get("password", ""))
	client_id = str(config.get("client_id", "godot"))
	keepalive_seconds = int(config.get("keepalive_seconds", 30))


func connect_to_broker() -> void:
	if host.is_empty():
		_disconnect("host vacio")
		return
	_peer = StreamPeerTCP.new()
	_last_disconnect_reason = ""
	var err := _peer.connect_to_host(host, port)
	if err != OK:
		_disconnect("connect_to_host error=%d host=%s port=%d" % [int(err), host, port])
		return
	_status = STATUS_CONNECTING
	_sent_connect = false
	_tcp_open_logged = false
	_pending_subscriptions.clear()
	_last_io_msec = Time.get_ticks_msec()


func is_broker_connected() -> bool:
	return _status == STATUS_CONNECTED


func get_connection_status() -> int:
	return _status


func get_last_disconnect_reason() -> String:
	return _last_disconnect_reason


func subscribe(topic: String) -> void:
	if topic.is_empty():
		return
	if not _subscriptions.has(topic):
		_subscriptions.append(topic)
	if _status == STATUS_CONNECTED:
		_send_subscribe(topic)


func publish(topic: String, payload: String) -> void:
	if _status != STATUS_CONNECTED:
		return
	var variable_header := _encode_utf8_string(topic)
	var body := PackedByteArray()
	body.append_array(variable_header)
	body.append_array(payload.to_utf8_buffer())
	_send_packet(0x30, body)


func poll() -> void:
	if _status == STATUS_NONE or _status == STATUS_DISCONNECTED:
		return

	_peer.poll()
	var peer_status := _peer.get_status()
	if peer_status == StreamPeerTCP.STATUS_ERROR or peer_status == StreamPeerTCP.STATUS_NONE:
		if _status != STATUS_DISCONNECTED:
			_disconnect("peer status=%d" % int(peer_status))
		return
	if _status == STATUS_CONNECTING and Time.get_ticks_msec() - _last_io_msec > 5000:
		_disconnect("timeout esperando CONNACK")
		return

	if peer_status == StreamPeerTCP.STATUS_CONNECTED and not _sent_connect:
		if not _tcp_open_logged:
			_log_event("tcp abierto %s:%d" % [host, port])
			_tcp_open_logged = true
		if not _send_connect():
			_disconnect("fallo enviando CONNECT")
			return
		_sent_connect = true
		_log_event("CONNECT enviado client_id=%s" % client_id)

	var available := _peer.get_available_bytes()
	if available > 0:
		var result := _peer.get_data(available)
		if int(result[0]) == OK:
			_rx_buffer.append_array(result[1])
			_last_io_msec = Time.get_ticks_msec()
			_parse_packets()
		else:
			_disconnect("get_data error=%d" % int(result[0]))
			return

	if _status == STATUS_CONNECTED and Time.get_ticks_msec() - _last_io_msec > keepalive_seconds * 500:
		if not _send_packet(0xC0, PackedByteArray()):
			_disconnect("fallo enviando PINGREQ")
			return
		_last_io_msec = Time.get_ticks_msec()
		_log_event("PINGREQ enviado")


func _send_connect() -> bool:
	var variable_header := PackedByteArray()
	variable_header.append_array(_encode_utf8_string("MQTT"))
	variable_header.append(4)

	var flags := 0x02
	if not username.is_empty():
		flags |= 0x80
	if not password.is_empty():
		flags |= 0x40
	variable_header.append(flags)
	variable_header.append((keepalive_seconds >> 8) & 0xFF)
	variable_header.append(keepalive_seconds & 0xFF)

	var payload := PackedByteArray()
	payload.append_array(_encode_utf8_string(client_id))
	if not username.is_empty():
		payload.append_array(_encode_utf8_string(username))
	if not password.is_empty():
		payload.append_array(_encode_utf8_string(password))

	var body := PackedByteArray()
	body.append_array(variable_header)
	body.append_array(payload)
	return _send_packet(0x10, body)


func _send_subscribe(topic: String) -> void:
	var body := PackedByteArray()
	var packet_id := _next_packet_id()
	body.append((packet_id >> 8) & 0xFF)
	body.append(packet_id & 0xFF)
	body.append_array(_encode_utf8_string(topic))
	body.append(0)
	if not _send_packet(0x82, body):
		_disconnect("fallo enviando SUBSCRIBE %s" % topic)
	else:
		_pending_subscriptions[packet_id] = topic
		_log_event("SUBSCRIBE enviado %s" % topic)


func _send_packet(packet_type: int, body: PackedByteArray) -> bool:
	var packet := PackedByteArray()
	packet.append(packet_type)
	packet.append_array(_encode_remaining_length(body.size()))
	packet.append_array(body)
	var err := _peer.put_data(packet)
	if err != OK:
		_last_disconnect_reason = "put_data packet=%d error=%d" % [packet_type, int(err)]
		return false
	return true


func _parse_packets() -> void:
	while _rx_buffer.size() >= 2:
		var remaining := 0
		var multiplier := 1
		var consumed := 1
		while true:
			if consumed >= _rx_buffer.size():
				return
			var encoded_byte := int(_rx_buffer[consumed])
			remaining += (encoded_byte & 127) * multiplier
			consumed += 1
			if (encoded_byte & 128) == 0:
				break
			multiplier *= 128
			if multiplier > 128 * 128 * 128:
				_disconnect("remaining length invalido")
				return

		var packet_size := consumed + remaining
		if _rx_buffer.size() < packet_size:
			return

		var packet_type := int(_rx_buffer[0]) & 0xF0
		var body := _rx_buffer.slice(consumed, packet_size)
		_rx_buffer = _rx_buffer.slice(packet_size)
		_handle_packet(packet_type, body)


func _handle_packet(packet_type: int, body: PackedByteArray) -> void:
	match packet_type:
		0x20:
			if body.size() >= 2 and int(body[1]) == 0:
				_status = STATUS_CONNECTED
				_log_event("CONNACK ok")
				connected.emit()
				for topic in _subscriptions:
					_send_subscribe(topic)
			else:
				var code: int = int(body[1]) if body.size() >= 2 else -1
				_disconnect("CONNACK rechazado code=%d %s" % [code, _connack_reason(code)])
		0x30:
			_handle_publish(body)
		0x90:
			_handle_suback(body)
		0xD0:
			_log_event("PINGRESP ok")
		_:
			pass


func _disconnect(reason: String) -> void:
	_last_disconnect_reason = reason
	_status = STATUS_DISCONNECTED
	_log_event("disconnect reason=%s" % reason)
	disconnected.emit()


func _log_event(text: String) -> void:
	log_event.emit(text)


func _handle_suback(body: PackedByteArray) -> void:
	if body.size() < 3:
		_log_event("SUBACK invalido")
		return
	var packet_id := (int(body[0]) << 8) | int(body[1])
	var return_code := int(body[2])
	var topic: String = str(_pending_subscriptions.get(packet_id, "packet_id=%d" % packet_id))
	_pending_subscriptions.erase(packet_id)
	if return_code <= 2:
		_log_event("SUBACK ok %s qos=%d" % [topic, return_code])
	else:
		_log_event("SUBACK rechazado %s code=%d" % [topic, return_code])


func _connack_reason(code: int) -> String:
	match code:
		1:
			return "protocolo inaceptable"
		2:
			return "client_id rechazado"
		3:
			return "servidor no disponible"
		4:
			return "usuario/password incorrectos"
		5:
			return "no autorizado"
		_:
			return "desconocido"


func _handle_publish(body: PackedByteArray) -> void:
	if body.size() < 2:
		return
	var topic_length := (int(body[0]) << 8) | int(body[1])
	if body.size() < 2 + topic_length:
		return
	var topic := body.slice(2, 2 + topic_length).get_string_from_utf8()
	var payload := body.slice(2 + topic_length).get_string_from_utf8()
	message.emit(topic, payload)


func _encode_utf8_string(value: String) -> PackedByteArray:
	var bytes := value.to_utf8_buffer()
	var out := PackedByteArray()
	out.append((bytes.size() >> 8) & 0xFF)
	out.append(bytes.size() & 0xFF)
	out.append_array(bytes)
	return out


func _encode_remaining_length(length: int) -> PackedByteArray:
	var out := PackedByteArray()
	var value := length
	while true:
		var encoded_byte := value % 128
		value = int(value / 128)
		if value > 0:
			encoded_byte |= 128
		out.append(encoded_byte)
		if value <= 0:
			break
	return out


func _next_packet_id() -> int:
	_packet_id += 1
	if _packet_id > 65535:
		_packet_id = 1
	return _packet_id
