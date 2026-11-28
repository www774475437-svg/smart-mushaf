"""Adds the account's own users as internal TestFlight testers of the app (App Store Connect API)."""
import json, os, time, urllib.request, urllib.error
import jwt

e = os.environ
tok = jwt.encode({'iss': e['ASC_ISSUER_ID'], 'iat': int(time.time()), 'exp': int(time.time()) + 900, 'aud': 'appstoreconnect-v1'},
                 e['ASC_KEY_P8'], algorithm='ES256', headers={'kid': e['ASC_KEY_ID']})


def api(method, path, body=None):
    req = urllib.request.Request('https://api.appstoreconnect.apple.com' + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={'Authorization': 'Bearer ' + tok, 'Content-Type': 'application/json'})
    try:
        r = urllib.request.urlopen(req, timeout=60).read()
        return json.loads(r) if r else {}
    except urllib.error.HTTPError as x:
        msg = x.read().decode()[:600]
        print('HTTP', x.code, method, path.split('?')[0], msg)
        return {'error': x.code, 'msg': msg}


app = api('GET', '/v1/apps?filter[bundleId]=com.abualathari.smartMushaf')['data'][0]
aid = app['id']
print('app', app['attributes']['name'], aid)
groups = api('GET', f'/v1/apps/{aid}/betaGroups').get('data', [])
g = next((x for x in groups if x['attributes'].get('isInternalGroup')), None)
if not g:
    g = api('POST', '/v1/betaGroups', {'data': {'type': 'betaGroups', 'attributes': {'name': 'Team', 'isInternalGroup': True, 'hasAccessToAllBuilds': True},
                                                 'relationships': {'app': {'data': {'type': 'apps', 'id': aid}}}}}).get('data')
print('group', g and g['attributes']['name'], g and g['id'])
users = api('GET', '/v1/users?limit=50').get('data', [])
for u in users:
    a = u['attributes']
    print('user', a.get('roles'))
    r = api('POST', '/v1/betaTesters', {'data': {'type': 'betaTesters',
            'attributes': {'email': a['username'], 'firstName': a.get('firstName') or 'Tester', 'lastName': a.get('lastName') or 'One'},
            'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': g['id']}]}}}})
    print('  added' if 'data' in r else '  not added (may already be a tester)')
ts = api('GET', f"/v1/betaGroups/{g['id']}/betaTesters").get('data', [])
print('testers in group:', len(ts), [t['attributes'].get('inviteType') for t in ts])
bs = api('GET', f'/v1/builds?filter[app]={aid}&sort=-uploadedDate&limit=5').get('data', [])
for b in bs:
    print('build', b['attributes']['version'], b['attributes']['processingState'], 'expired' if b['attributes'].get('expired') else '')
