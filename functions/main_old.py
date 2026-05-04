import time
import json
import requests
import pandas as pd
import numpy as np
from datetime import datetime
from cachetools import TTLCache
from firebase_functions import https_fn, scheduler_fn
from google.cloud import firestore
from google.cloud import secretmanager
from google.cloud import storage
from firebase_admin import initialize_app, auth
from cryptography.fernet import Fernet
import os
import io
import gc

# -----------------------------------------------------------------------------
# Inizializzazione e helper generici
# -----------------------------------------------------------------------------
_db = None
_secret_client = None
SESSION_CACHE = TTLCache(maxsize=100, ttl=8*60)

def get_db():
    global _db
    if _db is None:
        _db = firestore.Client(database='strikezonedb')
    return _db

def get_secret_client():
    global _secret_client
    if _secret_client is None:
        _secret_client = secretmanager.SecretManagerServiceClient()
    return _secret_client

_admin_initialized = False
def init_admin():
    global _admin_initialized
    if not _admin_initialized:
        try:
            initialize_app()
        except Exception:
            pass
        _admin_initialized = True

def get_encryption_key() -> bytes:
    project_id = os.environ.get('GCLOUD_PROJECT', 'strikezone-484a9')
    secret_name = f"projects/{project_id}/secrets/ENCRYPTION_KEY/versions/latest"
    client = get_secret_client()
    response = client.access_secret_version(request={"name": secret_name})
    return response.payload.data

def encrypt_data(data: str) -> str:
    cipher = Fernet(get_encryption_key())
    return cipher.encrypt(data.encode()).decode()

def decrypt_data(encrypted: str) -> str:
    cipher = Fernet(get_encryption_key())
    return cipher.decrypt(encrypted.encode()).decode()

def verify_token(req: https_fn.Request) -> str:
    auth_header = req.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        raise Exception("Missing or invalid Authorization header")
    id_token = auth_header.split(' ')[1]
    init_admin()
    decoded_token = auth.verify_id_token(id_token)
    return decoded_token['uid']

def cors_headers():
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
    }

# -----------------------------------------------------------------------------
# Funzioni esistenti per credenziali e proxy (invariate)
# -----------------------------------------------------------------------------
@https_fn.on_request()
def save_capital_credentials(req: https_fn.Request) -> https_fn.Response:
    headers = cors_headers()
    if req.method == 'OPTIONS':
        return https_fn.Response("", status=204, headers=headers)
    try:
        uid = verify_token(req)
    except Exception as e:
        return https_fn.Response(str(e), status=401, headers=headers)
    data = req.get_json()
    if not data or not all(k in data for k in ('apiKey', 'login', 'password')):
        return https_fn.Response("Missing fields", status=400, headers=headers)
    encrypted = {
        'apiKey': encrypt_data(data['apiKey']),
        'login': encrypt_data(data['login']),
        'password': encrypt_data(data['password']),
        'updatedAt': firestore.SERVER_TIMESTAMP
    }
    get_db().collection('capital_credentials').document(uid).set(encrypted)
    return https_fn.Response("OK", status=200, headers=headers)

@https_fn.on_request()
def get_capital_credentials(req: https_fn.Request) -> https_fn.Response:
    headers = cors_headers()
    if req.method == 'OPTIONS':
        return https_fn.Response("", status=204, headers=headers)
    try:
        uid = verify_token(req)
    except Exception as e:
        return https_fn.Response(str(e), status=401, headers=headers)
    doc = get_db().collection('capital_credentials').document(uid).get()
    if not doc.exists:
        return https_fn.Response(json.dumps({}), status=200, headers=headers)
    creds = doc.to_dict()
    decrypted = {
        'apiKey': decrypt_data(creds['apiKey']),
        'login': decrypt_data(creds['login']),
        'password': decrypt_data(creds['password']),
    }
    return https_fn.Response(json.dumps(decrypted), status=200, headers=headers)

@https_fn.on_request()
def delete_capital_credentials(req: https_fn.Request) -> https_fn.Response:
    headers = cors_headers()
    if req.method == 'OPTIONS':
        return https_fn.Response("", status=204, headers=headers)
    try:
        uid = verify_token(req)
    except Exception as e:
        return https_fn.Response(str(e), status=401, headers=headers)
    get_db().collection('capital_credentials').document(uid).delete()
    return https_fn.Response("OK", status=200, headers=headers)

def get_capital_session(uid: str):
    cached = SESSION_CACHE.get(uid)
    if cached:
        return cached[0], cached[1]
    doc = get_db().collection('capital_credentials').document(uid).get()
    if not doc.exists:
        return None, None
    creds = doc.to_dict()
    api_key = decrypt_data(creds['apiKey'])
    login = decrypt_data(creds['login'])
    password = decrypt_data(creds['password'])
    url = "https://api-capital.backend-capital.com/api/v1/session"
    headers = {"X-CAP-API-KEY": api_key, "Content-Type": "application/json"}
    payload = {"identifier": login, "password": password, "encryptedPassword": False}
    resp = requests.post(url, headers=headers, json=payload)
    if resp.status_code != 200:
        return None, None
    cst = resp.headers.get('CST')
    security_token = resp.headers.get('X-SECURITY-TOKEN')
    SESSION_CACHE[uid] = (cst, security_token, time.time())
    return cst, security_token

@https_fn.on_request()
def capital_com_proxy(req: https_fn.Request) -> https_fn.Response:
    headers = cors_headers()
    if req.method == 'OPTIONS':
        return https_fn.Response("", status=204, headers=headers)
    try:
        uid = verify_token(req)
    except Exception as e:
        return https_fn.Response(str(e), status=401, headers=headers)
    doc = get_db().collection('capital_credentials').document(uid).get()
    if not doc.exists:
        return https_fn.Response("No credentials", status=400, headers=headers)
    creds = doc.to_dict()
    try:
        api_key = decrypt_data(creds['apiKey'])
        login = decrypt_data(creds['login'])
        password = decrypt_data(creds['password'])
    except Exception as e:
        return https_fn.Response(f"Decrypt error: {e}", status=500, headers=headers)
    BASE_URL = "https://api-capital.backend-capital.com"
    def login_capital():
        r = requests.post(
            f"{BASE_URL}/api/v1/session",
            headers={"X-CAP-API-KEY": api_key, "Content-Type": "application/json"},
            json={"identifier": login, "password": password, "encryptedPassword": False}
        )
        if r.status_code != 200:
            raise Exception(r.text)
        return r.headers.get('CST'), r.headers.get('X-SECURITY-TOKEN')
    cached = SESSION_CACHE.get(uid)
    if cached:
        cst, security_token, _ = cached
    else:
        try:
            cst, security_token = login_capital()
            SESSION_CACHE[uid] = (cst, security_token, time.time())
        except Exception as e:
            return https_fn.Response(f"Auth failed: {e}", status=401, headers=headers)
    data = req.get_json()
    endpoint = data.get('endpoint')
    method = data.get('method', 'GET')
    body = data.get('body', {})
    url = f"{BASE_URL}{endpoint}"
    req_headers = {
        "X-CAP-API-KEY": api_key,
        "CST": cst,
        "X-SECURITY-TOKEN": security_token,
        "Content-Type": "application/json"
    }
    try:
        if method == 'GET':
            resp = requests.get(url, headers=req_headers)
        elif method == 'POST':
            resp = requests.post(url, headers=req_headers, json=body)
        elif method == 'PUT':
            resp = requests.put(url, headers=req_headers, json=body)
        elif method == 'DELETE':
            resp = requests.delete(url, headers=req_headers)
        else:
            return https_fn.Response("Unsupported method", status=400, headers=headers)
        if resp.status_code == 401:
            try:
                cst, security_token = login_capital()
                SESSION_CACHE[uid] = (cst, security_token, time.time())
                req_headers["CST"] = cst
                req_headers["X-SECURITY-TOKEN"] = security_token
                if method == 'GET':
                    resp = requests.get(url, headers=req_headers)
                elif method == 'POST':
                    resp = requests.post(url, headers=req_headers, json=body)
            except Exception as e:
                return https_fn.Response(f"Renew failed: {e}", status=401, headers=headers)
        try:
            response_data = resp.json()
        except:
            response_data = {"error": resp.text}
        return https_fn.Response(
            json.dumps({"status": resp.status_code, "data": response_data}),
            status=200,
            headers=headers
        )
    except Exception as e:
        return https_fn.Response(f"Proxy error: {e}", status=500, headers=headers)

# -----------------------------------------------------------------------------
# Funzioni per la strategia (calcolo indicatori)
# -----------------------------------------------------------------------------
def calculate_ema(series, period):
    return series.ewm(span=period, adjust=False).mean()

def calculate_rsi(series, period=14):
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.rolling(window=period).mean()
    avg_loss = loss.rolling(window=period).mean()
    rs = avg_gain / avg_loss
    rsi = 100 - (100 / (1 + rs))
    return rsi

def calculate_macd(series, fast=12, slow=26, signal=9):
    ema_fast = calculate_ema(series, fast)
    ema_slow = calculate_ema(series, slow)
    macd_line = ema_fast - ema_slow
    signal_line = calculate_ema(macd_line, signal)
    return macd_line - signal_line

def calculate_atr(df, period=14):
    high = df['high']
    low = df['low']
    close = df['close']
    tr = pd.DataFrame(index=df.index)
    tr['hl'] = high - low
    tr['hc'] = (high - close.shift()).abs()
    tr['lc'] = (low - close.shift()).abs()
    tr['tr'] = tr[['hl', 'hc', 'lc']].max(axis=1)
    return tr['tr'].rolling(window=period).mean()

def calculate_adx(df, period=14):
    high = df['high']
    low = df['low']
    plus_dm = high.diff()
    minus_dm = low.diff()
    plus_dm[plus_dm < 0] = 0
    minus_dm[minus_dm > 0] = 0
    minus_dm = -minus_dm
    atr = calculate_atr(df, period)
    atr_smooth = atr.rolling(window=period).mean()
    plus_di = 100 * (plus_dm.rolling(window=period).mean() / atr_smooth)
    minus_di = 100 * (minus_dm.rolling(window=period).mean() / atr_smooth)
    dx = 100 * (abs(plus_di - minus_di) / (plus_di + minus_di))
    return dx.rolling(window=period).mean()

def calculate_supertrend(df, period=10, multiplier=3.0):
    atr = calculate_atr(df, period)
    hl2 = (df['high'] + df['low']) / 2
    upper_band = hl2 + multiplier * atr
    lower_band = hl2 - multiplier * atr
    st_dir = pd.Series(index=df.index, dtype=float)
    st_dir.iloc[0] = 1
    for i in range(1, len(df)):
        if st_dir.iloc[i-1] == 1:
            if df['close'].iloc[i] <= lower_band.iloc[i]:
                st_dir.iloc[i] = -1
            else:
                st_dir.iloc[i] = 1
        else:
            if df['close'].iloc[i] >= upper_band.iloc[i]:
                st_dir.iloc[i] = 1
            else:
                st_dir.iloc[i] = -1
    return st_dir

def calculate_bollinger_bands(df, period=20, std=2.0):
    sma = df['close'].rolling(window=period).mean()
    std_dev = df['close'].rolling(window=period).std()
    return sma + std * std_dev, sma - std * std_dev

def compute_indicators(df: pd.DataFrame, config: dict):
    indicators = {}
    close = df['close']
    # EMA Long
    ema_long_cfg = config.get('indicators', {}).get('emaLong', {})
    if ema_long_cfg.get('enabled', False):
        length = ema_long_cfg.get('length', 200)
        df['emaLong'] = calculate_ema(close, length)
        indicators['emaLong'] = float(df['emaLong'].iloc[-1])
    else:
        indicators['emaLong'] = close.iloc[-1]
    # EMA Short
    ema_short_cfg = config.get('indicators', {}).get('emaShort', {})
    if ema_short_cfg.get('enabled', False):
        length = ema_short_cfg.get('length', 50)
        df['emaShort'] = calculate_ema(close, length)
        indicators['emaShort'] = float(df['emaShort'].iloc[-1])
    # SMA Signal (simple moving average)
    sma_cfg = config.get('indicators', {}).get('smaSignal', {})
    if sma_cfg.get('enabled', False):
        length = sma_cfg.get('length', 20)
        df['sma'] = close.rolling(window=length).mean()
        indicators['sma'] = float(df['sma'].iloc[-1])
    # RSI
    rsi_cfg = config.get('indicators', {}).get('rsi', {})
    if rsi_cfg.get('enabled', False):
        length = rsi_cfg.get('length', 14)
        df['rsi'] = calculate_rsi(close, length)
        indicators['rsi'] = float(df['rsi'].iloc[-1])
    # MACD
    macd_cfg = config.get('indicators', {}).get('macd', {})
    if macd_cfg.get('enabled', False):
        fast = macd_cfg.get('fast', 12)
        slow = macd_cfg.get('slow', 26)
        signal = macd_cfg.get('signal', 9)
        df['macd_hist'] = calculate_macd(close, fast, slow, signal)
        indicators['macd_hist'] = float(df['macd_hist'].iloc[-1])
    # ATR
    df['atr'] = calculate_atr(df, 14)
    indicators['atr'] = float(df['atr'].iloc[-1])
    # ADX (filtro)
    adx_cfg = config.get('filters', {}).get('adx', {})
    if adx_cfg.get('enabled', False):
        period = adx_cfg.get('period', 14)
        df['adx'] = calculate_adx(df, period)
        indicators['adx'] = float(df['adx'].iloc[-1])
    # SuperTrend
    st_cfg = config.get('filters', {}).get('superTrend', {})
    if st_cfg.get('enabled', False):
        period = st_cfg.get('period', 10)
        multiplier = st_cfg.get('multiplier', 3.0)
        df['st_dir'] = calculate_supertrend(df, period, multiplier)
        indicators['st_dir'] = int(df['st_dir'].iloc[-1])
    # Bollinger
    bb_cfg = config.get('filters', {}).get('bollinger', {})
    if bb_cfg.get('enabled', False):
        length = bb_cfg.get('length', 20)
        std = bb_cfg.get('std', 2.0)
        upper, lower = calculate_bollinger_bands(df, length, std)
        df['bb_upper'] = upper
        df['bb_lower'] = lower
        indicators['bb_upper'] = float(df['bb_upper'].iloc[-1])
        indicators['bb_lower'] = float(df['bb_lower'].iloc[-1])
    # ADR Score (semplificato)
    adr_cfg = config.get('indicators', {}).get('adrScore', {})
    if adr_cfg.get('enabled', False):
        avg_price = close.mean()
        adr_value = indicators['atr'] / (avg_price * 0.01) if avg_price > 0 else 0
        indicators['adr_score'] = min(adr_value, 1.0)
    return df, indicators

# -----------------------------------------------------------------------------
# Calcolo del punteggio finale della strategia (0-100)
# -----------------------------------------------------------------------------
def compute_score(indicators: dict, config: dict) -> float:
    """
    Calcola il punteggio in base agli indicatori abilitati e ai loro pesi.
    indicators: dizionario con i valori degli indicatori (già calcolati).
    config: configurazione completa della strategia (lettura da Firestore).
    Restituisce float tra 0 e 100.
    """
    score = 0.0
    total_weight = 0

    # --- EMA Long (distanza normalizzata) ---
    ema_long_cfg = config.get('indicators', {}).get('emaLong', {})
    if ema_long_cfg.get('enabled', False):
        weight = ema_long_cfg.get('weight', 25)
        total_weight += weight
        close = indicators.get('close', 0)
        ema = indicators.get('emaLong', close)
        atr = indicators.get('atr', 0.0001)
        distance = (close - ema) / atr
        # Normalizza tra -1 e 1 (ipotesi: movimenti tipici entro ±3 ATR)
        norm = max(-1, min(1, distance / 3.0))
        score += ((norm + 1) / 2) * weight

    # --- EMA Short (incrocio) ---
    ema_short_cfg = config.get('indicators', {}).get('emaShort', {})
    if ema_short_cfg.get('enabled', False):
        weight = ema_short_cfg.get('weight', 15)
        total_weight += weight
        cross = 1 if indicators.get('emaShort', 0) > indicators.get('emaLong', 0) else -1
        score += ((cross + 1) / 2) * weight

    # --- SMA Signal (posizione relativa) ---
    sma_cfg = config.get('indicators', {}).get('smaSignal', {})
    if sma_cfg.get('enabled', False):
        weight = sma_cfg.get('weight', 10)
        total_weight += weight
        sma = indicators.get('sma', indicators.get('close', 0))
        close = indicators.get('close', 0)
        above = 1 if close > sma else -1
        score += ((above + 1) / 2) * weight

    # --- RSI (normalizzato 0-1) ---
    rsi_cfg = config.get('indicators', {}).get('rsi', {})
    if rsi_cfg.get('enabled', False):
        weight = rsi_cfg.get('weight', 15)
        total_weight += weight
        rsi = indicators.get('rsi', 50)
        rsi_norm = rsi / 100.0
        score += rsi_norm * weight

    # --- MACD istogramma ---
    macd_cfg = config.get('indicators', {}).get('macd', {})
    if macd_cfg.get('enabled', False):
        weight = macd_cfg.get('weight', 10)
        total_weight += weight
        hist = indicators.get('macd_hist', 0)
        # Normalizzazione tipica per EUR/USD: valori tra -0.001 e 0.001
        hist_norm = max(-1, min(1, hist / 0.001))
        score += ((hist_norm + 1) / 2) * weight

    # --- ADR Score ---
    adr_cfg = config.get('indicators', {}).get('adrScore', {})
    if adr_cfg.get('enabled', False):
        weight = adr_cfg.get('weight', 15)
        total_weight += weight
        adr = indicators.get('adr_score', 0.5)
        score += adr * weight

    # --- Filtri (riducono il punteggio, non aggiungono peso) ---
    # ADX: penalizza se ADX basso
    adx_cfg = config.get('filters', {}).get('adx', {})
    if adx_cfg.get('enabled', False):
        adx = indicators.get('adx', 0)
        threshold = adx_cfg.get('threshold', 20)
        if adx < threshold:
            score *= 0.7

    # SuperTrend: penalizza se discorde dalla direzione base
    st_cfg = config.get('filters', {}).get('superTrend', {})
    if st_cfg.get('enabled', False):
        st_dir = indicators.get('st_dir', 0)
        close = indicators.get('close', 0)
        ema = indicators.get('emaLong', close)
        trend_up = close > ema
        if (trend_up and st_dir == -1) or (not trend_up and st_dir == 1):
            score *= 0.5

    # Bollinger: penalizza se prezzo fuori banda
    bb_cfg = config.get('filters', {}).get('bollinger', {})
    if bb_cfg.get('enabled', False):
        close = indicators.get('close', 0)
        upper = indicators.get('bb_upper', close)
        lower = indicators.get('bb_lower', close)
        if close > upper * 1.02 or close < lower * 0.98:
            score *= 0.8

    # Normalizzazione finale
    if total_weight > 0:
        score = (score / total_weight) * 100
    else:
        score = 50.0   # se nessun indicatore attivo

    return max(0.0, min(100.0, score))

# -----------------------------------------------------------------------------
# Altre funzioni (get_historical_prices, generate_signals, run_backtest)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OTTIMIZZAZIONE: Caricamento Parallelo Parquet
# -----------------------------------------------------------------------------
def load_timeframe_data(pair: str, resolution: str, bucket_name: str, start_date: datetime, end_date: datetime) -> pd.DataFrame:
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    res_upper = resolution.upper()

    tasks = []
    current = start_date.replace(day=1)
    while current <= end_date:
        tasks.append((current.year, f"{current.month:02d}"))
        if current.month == 12:
            current = current.replace(year=current.year+1, month=1)
        else:
            current = current.replace(month=current.month+1)

    def download_parquet(task):
        year, month_str = task
        # Struttura: EURUSD/{anno}/{timeframe}/{mese}_Ask.parquet
        base_path = f"{pair}/{year}/{res_upper}/{month_str}"

        try:
            b_blob = bucket.blob(f"{base_path}_Bid.parquet")
            a_blob = bucket.blob(f"{base_path}_Ask.parquet")

            if not b_blob.exists() or not a_blob.exists():
                return None

            df_bid = pd.read_parquet(io.BytesIO(b_blob.download_as_bytes()))
            df_ask = pd.read_parquet(io.BytesIO(a_blob.download_as_bytes()))

            # Rinomina colonne standard
            df_bid.columns = ['datetime', 'open_bid', 'high_bid', 'low_bid', 'close_bid']
            df_ask.columns = ['datetime', 'open_ask', 'high_ask', 'low_ask', 'close_ask']

            return pd.merge(df_bid, df_ask, on='datetime', how='inner')
        except Exception as e:
            print(f"Errore caricamento {base_path}: {e}")
            return None

    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(download_parquet, tasks))

    dfs = [d for d in results if d is not None]
    if not dfs: return pd.DataFrame()

    df = pd.concat(dfs, ignore_index=True)
    df = df[(df['datetime'] >= start_date) & (df['datetime'] <= end_date)]
    df['mid'] = (df['close_bid'] + df['close_ask']) / 2.0
    return df.sort_values('datetime').reset_index(drop=True)

def align_timeframes(df_op: pd.DataFrame, df_med: pd.DataFrame = None, df_long: pd.DataFrame = None) -> pd.DataFrame:
    """Allinea i timeframe medio e lungo al timeframe operativo usando merge_asof."""
    df_aligned = df_op.set_index('datetime')
    if df_med is not None:
        df_med = df_med.set_index('datetime')
        # Seleziona solo le colonne che iniziano con i nomi degli indicatori (es. 'ema_', 'rsi_', ...)
        # In questo esempio prendiamo tutte le colonne eccetto 'open_bid', 'high_bid', ...
        # Ma meglio rinominare gli indicatori con prefissi.
        # Per semplicità, prendiamo tutte le colonne che non sono di prezzo
        exclude = ['open_bid', 'high_bid', 'low_bid', 'close_bid', 'open_ask', 'high_ask', 'low_ask', 'close_ask', 'mid']
        med_cols = [c for c in df_med.columns if c not in exclude]
        if med_cols:
            df_aligned = pd.merge_asof(df_aligned, df_med[med_cols], left_index=True, right_index=True, direction='backward')
    if df_long is not None:
        df_long = df_long.set_index('datetime')
        long_cols = [c for c in df_long.columns if c not in exclude]
        if long_cols:
            df_aligned = pd.merge_asof(df_aligned, df_long[long_cols], left_index=True, right_index=True, direction='backward')
    df_aligned.reset_index(inplace=True)
    return df_aligned

def generate_signals_from_aligned(df: pd.DataFrame, config: dict, min_window: int = 200) -> list:
    signals = []
    for i in range(min_window, len(df)):
        window_df = df.iloc[i-min_window+1:i+1].copy()
        # Aggiungi colonne high, low, close per compatibilità con compute_indicators
        window_df['high'] = window_df['high_bid']
        window_df['low'] = window_df['low_bid']
        window_df['close'] = window_df['mid']

        window_df, indicators = compute_indicators(window_df, config)
        indicators['close'] = window_df['mid'].iloc[-1]
        score = compute_score(indicators, config)
        if score >= config['exitRules']['activationScore']:
            entry = window_df['mid'].iloc[-1]
            atr = indicators.get('atr', 0.0001)
            sl_mult = config['exitRules']['slAtrMult']
            tp_mult = config['exitRules']['tpAtrMult']
            direction = 'buy' if window_df['mid'].iloc[-1] > indicators['emaLong'] else 'sell'
            if direction == 'buy':
                sl = entry - atr * sl_mult
                tp = entry + atr * tp_mult
                real_entry = window_df['close_ask'].iloc[-1]
            else:
                sl = entry + atr * sl_mult
                tp = entry - atr * tp_mult
                real_entry = window_df['close_bid'].iloc[-1]
            signals.append({
                'timestamp': window_df['datetime'].iloc[-1],
                'type': direction,
                'entryPrice': real_entry,
                'stopLoss': sl,
                'takeProfit': tp,
                'score': score,
                'indicators': {k: v for k, v in indicators.items() if isinstance(v, (int, float))}
            })
    return signals

# -----------------------------------------------------------------------------
# OTTIMIZZAZIONE: Simulazione Vettorializzata
# -----------------------------------------------------------------------------
def simulate_signals_batch(signals: list, df_min: pd.DataFrame) -> list:
    if not signals or df_min.empty: return []

    results = []
    # Pre-indicizziamo per velocizzare i lookup
    df_min = df_min.sort_values('datetime').reset_index(drop=True)

    for sig in signals:
        entry_time = sig['timestamp']
        direction = sig['type']
        sl, tp = sig['stopLoss'], sig['takeProfit']

        # Slice dei dati dal momento del segnale
        sub = df_min[df_min['datetime'] >= entry_time]
        if sub.empty:
            results.append({**sig, 'exit_reason': 'no_data', 'realized_pips': 0})
            continue

        if direction == 'buy':
            hits_sl = sub[sub['close_bid'] <= sl]
            hits_tp = sub[sub['close_ask'] >= tp]
        else:
            hits_sl = sub[sub['close_ask'] >= sl]
            hits_tp = sub[sub['close_bid'] <= tp]

        time_sl = hits_sl['datetime'].min() if not hits_sl.empty else pd.Timestamp.max
        time_tp = hits_tp['datetime'].min() if not hits_tp.empty else pd.Timestamp.max

        if time_sl == pd.Timestamp.max and time_tp == pd.Timestamp.max:
            results.append({**sig, 'exit_reason': 'no_exit', 'realized_pips': 0})
        else:
            if time_sl < time_tp:
                exit_price, reason, exit_time = sl, 'SL', time_sl
            else:
                exit_price, reason, exit_time = tp, 'TP', time_tp

            pips = (exit_price - sig['entryPrice']) * 10000 if direction == 'buy' else (sig['entryPrice'] - exit_price) * 10000
            results.append({
                **sig, 'exit_reason': reason, 'exit_price': float(exit_price),
                'exit_time': exit_time, 'realized_pips': float(pips)
            })
    return results

# -----------------------------------------------------------------------------
# Funzione Principale run_backtest
# -----------------------------------------------------------------------------
@https_fn.on_request(memory=1024, timeout_sec=300)
def run_backtest(req: https_fn.Request) -> https_fn.Response:
    headers = cors_headers()
    if req.method == 'OPTIONS': return https_fn.Response("", status=204, headers=headers)

    logs = []
    def log(msg):
        logs.append(msg)
        print(msg)

    try:
        uid = verify_token(req)
        data = req.get_json()
        pair, start_str, end_str = data.get('pair'), data.get('startDate'), data.get('endDate')

        start_date = datetime.fromisoformat(start_str.replace('Z', '+00:00'))
        end_date = datetime.fromisoformat(end_str.replace('Z', '+00:00'))

        # Caricamento Configurazione
        config_doc = get_db().collection('strategy_configs').document(uid).get()
        if not config_doc.exists: return https_fn.Response("Config missing", status=400, headers=headers)
        config = config_doc.to_dict()

        bucket_name = "strikezone-484a9.firebasestorage.app"

        # Caricamento dati (Parquet)
        log("📥 Caricamento dati Parquet...")
        df_op = load_timeframe_data(pair, config['timeframes']['operativo'], bucket_name, start_date, end_date)

        if df_op.empty: return https_fn.Response("No data found", status=400, headers=headers)

        # Generazione Segnali (Logica esistente ottimizzata)
        # Nota: Qui dovresti inserire la tua funzione generate_signals_from_aligned
        log("🧠 Generazione segnali...")
        signals_raw = generate_signals_from_aligned(df_op, config) # Assicurati che riceva il DF corretto

        # Simulazione
        log("🎯 Simulazione batch...")
        df_min = load_timeframe_data(pair, '1M', bucket_name, start_date, end_date)
        results = simulate_signals_batch(signals_raw, df_min)

        # SALVATAGGIO OTTIMIZZATO (BATCH CHUNKING 500)
        log(f"💾 Salvataggio {len(results)} segnali...")
        test_ref = get_db().collection('test_signals')

        for i in range(0, len(results), 500):
            batch = get_db().batch()
            for res in results[i:i+500]:
                doc_ref = test_ref.document()
                # Conversione timestamp per Firestore
                res['timestamp'] = pd.to_datetime(res['timestamp'])
                if 'exit_time' in res and isinstance(res['exit_time'], pd.Timestamp):
                    res['exit_time'] = res['exit_time'].to_pydatetime()

                batch.set(doc_ref, {**res, 'userId': uid, 'pair': pair, 'createdAt': firestore.SERVER_TIMESTAMP})
            batch.commit()

        log("✅ Backtest completato con successo")
        gc.collect()
        return https_fn.Response(json.dumps({"generated": len(results), "logs": logs}), status=200, headers=headers)

    except Exception as e:
        log(f"❌ Errore critico: {str(e)}")
        return https_fn.Response(json.dumps({"error": str(e), "logs": logs}), status=500, headers=headers)