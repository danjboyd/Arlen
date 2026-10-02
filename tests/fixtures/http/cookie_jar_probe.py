import http.cookiejar
import json
import urllib.request

PORT = __PORT__
for method in ('GET', 'HEAD'):
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                        urllib.request.HTTPCookieProcessor(jar))

    def request(path, method='GET'):
        req = urllib.request.Request('http://127.0.0.1:%d%s' % (PORT, path), method=method)
        with opener.open(req, timeout=5) as response:
            assert response.status == 200
            assert response.headers.get('X-Injected') is None
            return response.headers.get_all('Set-Cookie') or [], response.read()

    cookies, body = request('/issue', method)
    assert len(cookies) == 2, cookies
    assert cookies[0].startswith('remember=device;'), cookies
    assert cookies[1].startswith('fixture_session='), cookies
    assert ('Expires=Wed, 09 Jun 2032' in cookies[0]), cookies
    assert body == (b'' if method == 'HEAD' else b'issued'), body
    by_name = {c.name: c for c in jar}
    assert set(by_name) == {'remember', 'fixture_session'}, by_name
    assert by_name['remember'].path == '/account'
    assert by_name['remember'].domain_specified
    assert not by_name['fixture_session'].domain_specified
    cookies, body = request('/account/check')
    assert not cookies, cookies  # Unchanged sessions do not issue another cookie.
    data = json.loads(body)
    assert data['user'] == 'fixture', data
    assert data['cookies']['remember'] == 'device', data
    _, body = request('/outside')
    assert 'remember' not in json.loads(body)['cookies']
    cookies, _ = request('/legacy')
    assert len(cookies) == 1, cookies
    assert len(jar) == 3, list(jar)
    cookies, body = request('/account/logout', method)
    assert len(cookies) == 3, cookies
    assert [c.split('=', 1)[0] for c in cookies] == ['remember', 'legacy', 'fixture_session']
    assert all('Max-Age=0' in c for c in cookies), cookies
    assert body == (b'' if method == 'HEAD' else b'logged out'), body
    assert len(jar) == 0, list(jar)
    _, body = request('/account/check')
    assert json.loads(body) == {'cookies': {}, 'user': ''}, body
print('cookie jar issuance, scope, session, logout and HEAD checks passed')
