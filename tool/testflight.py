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

# ---------------- a public link for outside testers ----------------
if os.environ.get('PUBLIC') == '1':
    ext = next((x for x in api('GET', f'/v1/apps/{aid}/betaGroups').get('data', []) if not x['attributes'].get('isInternalGroup')), None)
    if not ext:
        ext = api('POST', '/v1/betaGroups', {'data': {'type': 'betaGroups',
              'attributes': {'name': 'Public', 'publicLinkEnabled': True, 'publicLinkLimitEnabled': False, 'feedbackEnabled': True},
              'relationships': {'app': {'data': {'type': 'apps', 'id': aid}}}}}).get('data')
    elif not ext['attributes'].get('publicLinkEnabled'):
        ext = api('PATCH', f"/v1/betaGroups/{ext['id']}", {'data': {'type': 'betaGroups', 'id': ext['id'], 'attributes': {'publicLinkEnabled': True}}}).get('data')
    print('public group', ext and ext['attributes'].get('publicLink'))
    owner = users[0]['attributes']
    det = api('GET', f'/v1/apps/{aid}/betaAppReviewDetail').get('data')
    if det:
        a = det['attributes']
        print('review contact set:', {k: bool(a.get(k)) for k in ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail')})
        need = {}
        if not a.get('contactFirstName'): need['contactFirstName'] = owner.get('firstName') or 'Ahmed'
        if not a.get('contactLastName'): need['contactLastName'] = owner.get('lastName') or 'Developer'
        if not a.get('contactEmail'): need['contactEmail'] = owner['username']
        if os.environ.get('PHONE') and not a.get('contactPhone'): need['contactPhone'] = os.environ['PHONE']
        need['demoAccountRequired'] = False
        api('PATCH', f"/v1/betaAppReviewDetails/{det['id']}", {'data': {'type': 'betaAppReviewDetails', 'id': det['id'], 'attributes': need}})
    locs = api('GET', f'/v1/apps/{aid}/betaAppLocalizations').get('data', [])
    desc = 'مصحف المدينة مع التلاوات والتفاسير، وتسميع الحفظ بالصوت مع كشف الأخطاء. جرّب القراءة والتسميع وأخبرنا بما تجده.'
    if locs:
        l = locs[0]
        api('PATCH', f"/v1/betaAppLocalizations/{l['id']}", {'data': {'type': 'betaAppLocalizations', 'id': l['id'],
            'attributes': {'description': desc, 'feedbackEmail': owner['username']}}})
    else:
        api('POST', '/v1/betaAppLocalizations', {'data': {'type': 'betaAppLocalizations',
            'attributes': {'locale': 'ar-SA', 'description': desc, 'feedbackEmail': owner['username']},
            'relationships': {'app': {'data': {'type': 'apps', 'id': aid}}}}})
    valid = [b for b in bs if b['attributes']['processingState'] == 'VALID' and not b['attributes'].get('expired')]
    if valid and ext:
        b = valid[0]
        bl = api('GET', f"/v1/builds/{b['id']}/betaBuildLocalizations").get('data', [])
        what = 'جرّب قراءة المصحف، والتسميع بالصوت، والتلاوات والتفاسير.'
        if bl:
            api('PATCH', f"/v1/betaBuildLocalizations/{bl[0]['id']}", {'data': {'type': 'betaBuildLocalizations', 'id': bl[0]['id'], 'attributes': {'whatsNew': what}}})
        else:
            api('POST', '/v1/betaBuildLocalizations', {'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': 'ar-SA', 'whatsNew': what},
                'relationships': {'build': {'data': {'type': 'builds', 'id': b['id']}}}}})
        api('POST', f"/v1/betaGroups/{ext['id']}/relationships/builds", {'data': [{'type': 'builds', 'id': b['id']}]})
        r = api('POST', '/v1/betaAppReviewSubmissions', {'data': {'type': 'betaAppReviewSubmissions',
                'relationships': {'build': {'data': {'type': 'builds', 'id': b['id']}}}}})
        print('submitted build', b['attributes']['version'], 'for beta review:', r.get('data', {}).get('attributes') or 'see error above')
    ext = api('GET', f"/v1/betaGroups/{ext['id']}").get('data')
    print('PUBLIC LINK', ext['attributes'].get('publicLink'))
