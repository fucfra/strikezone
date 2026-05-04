import functions_framework
from google.cloud import firestore
from google.cloud import secretmanager
from firebase_admin import initialize_app, auth
from cryptography.fernet import Fernet
import requests
import json
import os

# Inizializza Firebase Admin (per la verifica token)
initialize_app()

# Client
db = firestore.Client()
secret_client = secretmanager.SecretManagerServiceClient()

# Ottiene la chiave di crittografia da Secret Manager
def get_encryption_key() -> bytes:
    project_id = os.environ.get('GCLOUD_PROJECT')
    secret_name = f"projects/{project_id}/secrets/ENCRYPTION_KEY/versions/latest"
    response = secret_client.access_secret_version(request={"name": secret_name})
    return response.payload.data

# Funzioni crittografiche
def encrypt_data(data: str) -> str:
    cipher = Fernet(get_encryption_key())
    return cipher.encrypt(data.encode()).decode()

def decrypt_data(encrypted: str) -> str:
    cipher = Fernet(get_encryption_key())
    return cipher.decrypt(encrypted.encode()).decode()

# Verifica il token Firebase e restituisce l'uid
def verify_token(request) -> str:
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        raise Exception("Missing or invalid Authorization header")
    id_token = auth_header.split(' ')[1]
    decoded_token = auth.verify_id_token(id_token)
    return decoded_token['uid']

# ---------- CLOUD FUNCTIONS ----------

@functions_framework.http
def save_capital_credentials(request):
    """Salva le credenziali di Capital.com per l'utente autenticato."""
    try:
        uid = verify_token(request)
    except Exception as e:
        return (str(e), 401)

    data = request.get_json()
    if not data or not all(k in data for k in ('apiKey', 'login', 'password')):
        return ("Missing fields: apiKey, login, password", 400)

    encrypted = {
        'apiKey': encrypt_data(data['apiKey']),
        'login': encrypt_data(data['login']),
        'password': encrypt_data(data['password']),
        'updatedAt': firestore.SERVER_TIMESTAMP
    }
    db.collection('capital_credentials').document(uid).set(encrypted)
    return ("OK", 200)

@functions_framework.http
def get_capital_credentials(request):
    """Restituisce le credenziali decrittografate (chiamata interna, ma protetta)."""
    try:
        uid = verify_token(request)
    except Exception as e:
        return (str(e), 401)

    doc = db.collection('capital_credentials').document(uid).get()
    if not doc.exists:
        return (json.dumps({}), 200)
    creds = doc.to_dict()
    decrypted = {
        'apiKey': decrypt_data(creds['apiKey']),
        'login': decrypt_data(creds['login']),
        'password': decrypt_data(creds['password']),
    }
    return (json.dumps(decrypted), 200)

@functions_framework.http
def delete_capital_credentials(request):
    try:
        uid = verify_token(request)
    except Exception as e:
        return (str(e), 401)

    db.collection('capital_credentials').document(uid).delete()
    return ("OK", 200)

@functions_framework.http
def capital_com_proxy(request):
    """
    Proxy per chiamare le API di Capital.com.
    Riceve nel body: { "endpoint": "/api/v1/...", "method": "GET", "body": {...} }
    """
    try:
        uid = verify_token(request)
    except Exception as e:
        return (str(e), 401)

    # Recupera le credenziali decrittografate
    doc = db.collection('capital_credentials').document(uid).get()
    if not doc.exists:
        return ("Capital.com credentials not found. Please save them first.", 400)
    creds = doc.to_dict()
    api_key = decrypt_data(creds['apiKey'])
    login = decrypt_data(creds['login'])
    password = decrypt_data(creds['password'])

    # Effettua il login a Capital.com per ottenere i token di sessione (CST, X-SECURITY-TOKEN)
    # Nota: per mantenere performance, potresti cacheare i token in una mappa (ma attento alla sicurezza)
    session_resp = requests.post(
        "https://api-capital.backend-capital.com/api/v1/session",
        headers={"X-CAP-API-KEY": api_key},
        json={"identifier": login, "password": password}
    )
    if session_resp.status_code != 200:
        return ("Capital.com authentication failed", 401)
    cst = session_resp.headers.get('CST')
    security_token = session_resp.headers.get('X-SECURITY-TOKEN')

    # Prepara la chiamata API richiesta dal client
    data = request.get_json()
    endpoint = data.get('endpoint')
    method = data.get('method', 'GET')
    body = data.get('body', {})

    url = f"https://api-capital.backend-capital.com{endpoint}"
    headers = {
        "X-CAP-API-KEY": api_key,
        "CST": cst,
        "X-SECURITY-TOKEN": security_token,
        "Content-Type": "application/json"
    }

    try:
        if method == 'GET':
            resp = requests.get(url, headers=headers)
        elif method == 'POST':
            resp = requests.post(url, headers=headers, json=body)
        elif method == 'PUT':
            resp = requests.put(url, headers=headers, json=body)
        elif method == 'DELETE':
            resp = requests.delete(url, headers=headers)
        else:
            return ("Unsupported method", 400)

        # Restituisce la risposta al client
        return (json.dumps({"status": resp.status_code, "data": resp.json()}), 200)
    except Exception as e:
        return (f"Proxy error: {str(e)}", 500)