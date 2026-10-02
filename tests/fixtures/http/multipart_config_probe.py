import http.client

PORT = __PORT__


def request(body, expected):
    connection = http.client.HTTPConnection("127.0.0.1", PORT, timeout=10)
    try:
        connection.request("GET", "/healthz", body, {
            "Content-Type": "multipart/form-data; boundary=Aa",
            "Connection": "close",
        })
        response = connection.getresponse()
        assert response.status == expected, (response.status, response.read())
        response.read()
    finally:
        connection.close()


field = b'--Aa\r\nContent-Disposition: form-data; name="x"\r\n\r\nx\r\n'
file = b'--Aa\r\nContent-Disposition: form-data; name="file"; filename="a.bin"\r\n\r\n'
# These requests use a real old-style app.plist, including raised transport and
# file limits. Equality is accepted and one byte/part over is rejected.
request(field * 16 + b'--Aa--', 200)
request(field * 17 + b'--Aa--', 413)
request(file + b'x' * 5242880 + b'\r\n--Aa--', 200)
request(file + b'x' * 5242881 + b'\r\n--Aa--', 413)
request(field + b'--Aa--', 200)
print('configured multipart checks passed')
