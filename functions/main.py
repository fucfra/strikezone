"""
Cloud Functions strategia utente (allineate a StrategyConfigModel / strategy_configs).

- save_strategy_config (POST): scrittura merge
- get_strategy_config (GET): lettura documento per uid del token
- run_backtest (callable): carica Parquet GCS per i timeframe in strategy_configs; log righe per slot.
  Avanzamento UX: aggiorna `backtest_progress/{uid}` (stage, detail, pair) durante l'esecuzione;
  nella simulazione 1m lo stage `simulate_1m` include avanzamento per segnale e (se necessario) per barre.
  Carichi I/O per risoluzioni distinte: opzionale con STRIKEZONE_PARALLEL_PARQUET
  (1/true/yes oppure intero 2–8 = max worker; su emulatore macOS usare con cautela).
- save_live_signal (callable): scrive signals con verifica maxSimultaneousTrades (stesso limite del backtest)
- run_live_signals_from_capital (callable): OHLC da Capital /prices, allineamento TF come backtest,
  generazione segnali (stessa logica _generate_test_signals), salva solo l’ultima barra su `signals` (live).
- on_signal_document_created (trigger Firestore onCreate signals/*): enforcement max posizioni + notifica FCM
  agli `fcmTokens` in `users/{uid}`; se breakEven.active e trailingStop.active in strategy_configs, seconda notifica SL manuale.
  Un solo trigger sul path `signals/*` (due trigger Gen2 sullo stesso documento possono fallire al deploy Eventarc).
- scheduled_update_live_signals_sl (scheduler ogni minuto UTC): segnali live aperti con break-even e/o trailing
  attivi in strategy_configs; OHLC 1m Capital; aggiorna `stopLoss` + `liveSlTrack` su Firestore; FCM su cambio SL
  o chiusura simulata (coppia + apertura UTC). Disabilitabile con STRIKEZONE_DISABLE_LIVE_SL_SCHEDULER=1.
- get_capital_credentials / save_capital_credentials / delete_capital_credentials (POST):
  credenziali Capital.com come da setting_screen / SettingsViewModel
- capital_com_proxy (POST): proxy verso API Capital.com (HTTP, opzionale)
- capital_com_proxy_call (callable): stesso proxy, preferibile da Flutter (SDK / emulatore)
  CORS: cors_origins * sulla callable. Debug verso Capital (API key / password in log): solo se
  CAPITAL_COM_DEBUG_LOG_SECRETS=1 nell'emulatore — mai in produzione.
  Nota Capital.com (REST): GET /api/v1/prices/{epic} fornisce OHLC storici per resolution;
  non espone RSI/MACD/EMA pre-calcolati — riusare la logica indicatori di questo modulo (Parquet/live).

Campi tipici: userId, timeframes, indicators, filters, exitRules, updatedAt
"""

from __future__ import annotations

import os
import sys


def _darwin_emulator_avoid_scproxy_fork_crash() -> None:
    """
    L'emulatore Firebase fa fork dei worker Python. Su macOS, urllib può risolvere i proxy
    via _scproxy → SystemConfiguration (anche da thread worker): nel processo figlio questo
    produce spesso SIGSEGV ("crashed on child side of fork pre-exec"). Usare solo variabili
    d'ambiente evita del tutto _scproxy. Override disattivabile con STRIKEZONE_PRESERVE_SYSTEM_PROXY=1.
    Deve essere eseguito prima di import che aprono rete (google.cloud.storage, grpc, ecc.).
    """
    if sys.platform != "darwin":
        return
    if (os.environ.get("FUNCTIONS_EMULATOR") or "").strip().lower() not in ("true", "1"):
        return
    if (os.environ.get("STRIKEZONE_PRESERVE_SYSTEM_PROXY") or "").strip().lower() in (
        "1",
        "true",
        "yes",
    ):
        return
    # Forza percorso "env-only" per qualsiasi client che tenta auto-discovery proxy.
    os.environ.setdefault("NO_PROXY", "*")
    os.environ.setdefault("no_proxy", "*")
    os.environ.setdefault("HTTP_PROXY", "")
    os.environ.setdefault("http_proxy", "")
    os.environ.setdefault("HTTPS_PROXY", "")
    os.environ.setdefault("https_proxy", "")
    os.environ.setdefault("ALL_PROXY", "")
    os.environ.setdefault("all_proxy", "")
    os.environ.setdefault("GRPC_PROXY_EXP", "")
    os.environ.setdefault("grpc_proxy", "")

    import urllib.request

    urllib.request.getproxies = urllib.request.getproxies_environment  # type: ignore[method-assign]
    # Alcune librerie chiamano direttamente i path Darwin-specific.
    if hasattr(urllib.request, "getproxies_macosx_sysconf"):
        urllib.request.getproxies_macosx_sysconf = (  # type: ignore[attr-defined]
            urllib.request.getproxies_environment
        )
    if hasattr(urllib.request, "proxy_bypass_macosx_sysconf"):
        urllib.request.proxy_bypass_macosx_sysconf = lambda host: True  # type: ignore[attr-defined]


_darwin_emulator_avoid_scproxy_fork_crash()

import base64
import copy
import io
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
import logging
import threading
import time
from datetime import datetime, timezone
from typing import Any

import numpy as np
import pandas as pd  # pyright: ignore[reportMissingImports]
import requests  # pyright: ignore[reportMissingImports,reportMissingModuleSource]
from cryptography.fernet import Fernet, InvalidToken
from firebase_admin import auth, initialize_app, messaging
from firebase_functions import firestore_fn, https_fn, scheduler_fn
from firebase_functions.https_fn import FunctionsErrorCode, HttpsError
from firebase_functions.options import CorsOptions, set_global_options
from google.cloud import firestore, secretmanager, storage

# Gen2 / Cloud Run: limite istanze di default per ridurre errori transienti di quota al deploy.
set_global_options(max_instances=10)

_db = None
_admin_initialized = False
_secret_client = None
_logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)
_logger.setLevel(logging.INFO)


class TTLCache:
    """
    Cache TTL minimale (drop-in per get/set usati in questo file).
    Evita dipendenza runtime da cachetools nell'ambiente locale.
    """

    def __init__(self, maxsize: int, ttl: float):
        self._maxsize = maxsize
        self._ttl = ttl
        self._store: dict[Any, tuple[Any, float]] = {}
        self._lock = threading.Lock()

    def _purge_expired(self, now: float) -> None:
        expired = [k for k, (_, exp) in self._store.items() if exp <= now]
        for key in expired:
            self._store.pop(key, None)

    def get(self, key: Any, default: Any = None) -> Any:
        now = time.time()
        with self._lock:
            self._purge_expired(now)
            entry = self._store.get(key)
            if entry is None:
                return default
            value, _ = entry
            return value

    def __setitem__(self, key: Any, value: Any) -> None:
        now = time.time()
        with self._lock:
            self._purge_expired(now)
            if len(self._store) >= self._maxsize and key not in self._store:
                oldest_key = next(iter(self._store))
                self._store.pop(oldest_key, None)
            self._store[key] = (value, now + self._ttl)


# Sessioni Capital.com in-memory (stesso uid → CST + token fino a TTL).
SESSION_CACHE: TTLCache[str, tuple[str | None, str | None, float]] = TTLCache(
    maxsize=100, ttl=8 * 60
)
CAPITAL_API_BASE = "https://api-capital.backend-capital.com"

# L'emulatore Functions fa fork del worker Python. Su macOS, requests/urllib3 possono
# invocare _scproxy → SystemConfiguration (CFPreferences da thread); nel child dopo fork
# questo produce SIGSEGV ("crashed on child side of fork pre-exec"). trust_env=False
# salta il rilevamento proxy di sistema per queste sole chiamate HTTPS.
_CAPITAL_HTTP_SESSION = requests.Session()
_CAPITAL_HTTP_SESSION.trust_env = False


def _capital_com_debug_log_secrets() -> bool:
    """Solo per debug locale: logga API key, password, token Capital. Mai abilitare in cloud."""
    v = (os.environ.get("CAPITAL_COM_DEBUG_LOG_SECRETS") or "").strip().lower()
    return v in ("1", "true", "yes")


# Richieste parallele verso Capital.com causano spesso socket hang up / worker instabili
# nell'emulatore Functions su macOS: una sola sessione outbound alla volta per processo.
_CAPITAL_PROXY_GLOBAL_LOCK = threading.Lock()

DEFAULT_PROJECT_ID = os.environ.get("GCLOUD_PROJECT", "strikezone-484a9")

# Bucket storico OHLC:
# historical_data/{pair}/{resolution}/{year}/{month}_Bid|Ask.parquet
_BACKTEST_GCS_BUCKET = os.environ.get(
    "BACKTEST_GCS_BUCKET",
    f"{DEFAULT_PROJECT_ID}.firebasestorage.app",
)


def _firestore_database_id() -> str:
    """
    Allineato a lib/core/config/firebase_runtime_config.dart:
    - override esplicito FIRESTORE_DATABASE_ID
    - in emulatore (host Firestore e/o Auth): database (default), come il client Flutter
    - in cloud / senza emulatori: strikezonedb
    """
    explicit = (os.environ.get("FIRESTORE_DATABASE_ID") or "").strip()
    if explicit:
        return explicit
    if os.environ.get("FIRESTORE_EMULATOR_HOST") or os.environ.get(
        "FIREBASE_AUTH_EMULATOR_HOST"
    ):
        return "(default)"
    return "strikezonedb"


def get_db() -> firestore.Client:
    global _db
    if _db is None:
        _db = firestore.Client(database=_firestore_database_id())
    return _db


def _write_backtest_progress(uid: str, pair_upper: str, stage: str, detail: str = "") -> None:
    """Aggiorna avanzamento `run_backtest` (documento letto in tempo reale dalla schermata Test)."""
    try:
        get_db().collection("backtest_progress").document(uid).set(
            {
                "stage": stage,
                "detail": detail,
                "pair": pair_upper,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
    except Exception:
        _logger.warning(
            "backtest_progress write failed uid=%s stage=%s",
            uid,
            stage,
            exc_info=True,
        )


def _simulate_1m_progress_maybe(
    prog: dict[str, Any] | None,
    detail: str,
    *,
    force: bool = False,
) -> None:
    """
    Durante `_simulate_signal_closures_1m`, aggiorna `backtest_progress` con stage `simulate_1m`.
    Throttle temporale (default ~1,15s) per limitare scritture Firestore durante loop lunghi.
    """
    if not prog or not prog.get("uid") or not prog.get("pair"):
        return
    now = time.monotonic()
    interval = float(prog.get("interval", 1.15))
    if not force and (now - float(prog.get("last", 0.0))) < interval:
        return
    prog["last"] = now
    _write_backtest_progress(
        str(prog["uid"]),
        str(prog["pair"]),
        "simulate_1m",
        detail,
    )


def get_secret_client() -> secretmanager.SecretManagerServiceClient:
    global _secret_client
    if _secret_client is None:
        _secret_client = secretmanager.SecretManagerServiceClient()
    return _secret_client


def _running_firebase_emulators() -> bool:
    return bool(
        os.environ.get("FIRESTORE_EMULATOR_HOST")
        or os.environ.get("FIREBASE_AUTH_EMULATOR_HOST")
    )


# Chiave Fernet fissa solo per emulatori: materiale esattamente 32 byte → url-safe b64.
_EMULATOR_CAPITAL_FERNET_KEY = base64.urlsafe_b64encode(
    b"strikezone-capital-local-dev-key"
).decode("ascii")


def _fernet() -> Fernet:
    """
    Ordine: env CAPITAL_CREDENTIALS_FERNET_KEY → in emulatore chiave dev locale
    (Secret Manager non è raggiungibile / non va usato in locale) → Secret Manager in cloud.
    """
    env_key = (os.environ.get("CAPITAL_CREDENTIALS_FERNET_KEY") or "").strip()
    if env_key:
        return Fernet(env_key.encode("utf-8"))
    if _running_firebase_emulators():
        return Fernet(_EMULATOR_CAPITAL_FERNET_KEY.encode("ascii"))
    secret_name = (
        f"projects/{DEFAULT_PROJECT_ID}/secrets/ENCRYPTION_KEY/versions/latest"
    )
    raw = get_secret_client().access_secret_version(request={"name": secret_name})
    key_bytes = raw.payload.data
    if isinstance(key_bytes, str):
        key_bytes = key_bytes.encode("utf-8")
    return Fernet(key_bytes)


def _encrypt_field(value: str) -> str:
    return _fernet().encrypt(value.encode("utf-8")).decode("utf-8")


def _decrypt_field(blob: str) -> str:
    return _fernet().decrypt(blob.encode("utf-8")).decode("utf-8")


def init_admin() -> None:
    global _admin_initialized
    if not _admin_initialized:
        try:
            initialize_app()
        except Exception:
            pass
        _admin_initialized = True


# I callable verificano l'id token prima che parta l'handler: serve la default app Admin.
init_admin()


def verify_token(req: https_fn.Request) -> str:
    if os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"):
        auth_header = req.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            raise ValueError("Autenticazione richiesta")
        id_token = auth_header.split(" ", 1)[1]
        try:
            parts = id_token.split(".")
            if len(parts) < 2:
                raise ValueError("Token non valido")
            payload = parts[1] + "=" * (-len(parts[1]) % 4)
            decoded = base64.urlsafe_b64decode(payload.encode("utf-8")).decode("utf-8")
            claims = json.loads(decoded)
            uid = claims.get("user_id") or claims.get("uid") or claims.get("sub")
            if not uid:
                raise ValueError("UID mancante nel token")
            return uid
        except Exception as e:
            raise ValueError(f"Token emulator non valido: {e}") from e

    auth_header = req.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise ValueError("Missing or invalid Authorization header")
    id_token = auth_header.split(" ", 1)[1]
    init_admin()
    decoded = auth.verify_id_token(id_token)
    return decoded["uid"]


def cors_headers(req: https_fn.Request | None = None) -> dict:
    """
    CORS espliciti su ogni risposta (Flutter web + emulatore).
    Eco di Access-Control-Request-Headers sul preflight quando presente.
    """
    allow_headers = (
        "Authorization, Content-Type, Accept, Origin, X-Requested-With, "
        "X-Firebase-AppCheck, X-Firebase-Locale, X-Client-Version"
    )
    if req is not None:
        rh = req.headers.get("Access-Control-Request-Headers")
        if rh:
            allow_headers = rh
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS, PUT, DELETE",
        "Access-Control-Allow-Headers": allow_headers,
        "Access-Control-Max-Age": "86400",
        "Content-Type": "application/json",
    }


def parse_request_json(req: https_fn.Request) -> dict:
    body = req.get_json(silent=True)
    if body is None:
        raw = req.data or b""
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", errors="ignore")
        raw = (raw or "").strip()
        if raw:
            try:
                body = json.loads(raw)
            except Exception:
                body = {}
        else:
            body = {}
    if not isinstance(body, dict):
        return {}
    if isinstance(body.get("data"), dict):
        return body["data"]
    return body


def _sanitize_strategy_payload(data: dict) -> dict:
    """Mantiene solo i blocchi previsti dal modello Flutter; ignora chiavi estranee."""
    out: dict = {}
    for key in ("timeframes", "indicators", "filters", "exitRules"):
        if key in data and isinstance(data[key], dict):
            out[key] = data[key]
    return out


def _serialize_strategy_doc(obj: Any) -> Any:
    """Converte valori Firestore (Timestamp, datetime, ecc.) in tipi JSON-safe."""
    if obj is None or isinstance(obj, (bool, int, float, str)):
        return obj
    if isinstance(obj, dict):
        return {k: _serialize_strategy_doc(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_serialize_strategy_doc(v) for v in obj]
    if isinstance(obj, datetime):
        return obj.isoformat()
    if hasattr(obj, "isoformat"):
        try:
            return obj.isoformat()
        except (TypeError, ValueError):
            pass
    return str(obj)


def _callable_data(req: https_fn.CallableRequest) -> dict:
    raw = req.data
    return raw if isinstance(raw, dict) else {}


def _parse_iso_datetime(value: Any) -> datetime:
    if not value or not isinstance(value, str):
        raise ValueError("data mancante o non stringa")
    return datetime.fromisoformat(value.strip().replace("Z", "+00:00"))


def _to_utc_timestamp(value: Any) -> pd.Timestamp:
    """Timestamp UTC: accetta naive (localizza) o tz-aware (converte), evita tz= su valori già tz-aware."""
    t = pd.Timestamp(value)
    if t.tz is None:
        return t.tz_localize("UTC")
    return t.tz_convert("UTC")


# FX backtest: lotto standard = 100_000 unità di valuta base (come MT4/MT5).
_FX_UNITS_PER_LOT = 100_000.0
# Conversione P&L → EUR quando manca una coppia incrociata esplicita nel backtest.
_EUR_USD_FALLBACK = 1.09
_EUR_JPY_FALLBACK = 165.0


def _normalize_pair_symbols(pair: str) -> str:
    return "".join(c for c in (pair or "").upper() if c.isalpha())


def _split_fx_pair(norm: str) -> tuple[str, str] | None:
    if len(norm) != 6:
        return None
    return norm[:3], norm[3:]


def _pip_size_for_quote(quote_ccy: str) -> float:
    return 0.01 if (quote_ccy or "").upper() == "JPY" else 0.0001


def _price_diff_to_pips(price_diff: float, quote_ccy: str) -> float:
    ps = _pip_size_for_quote(quote_ccy)
    return float(price_diff / ps) if ps else 0.0


def _bar_spread_pips(row: pd.Series, quote_ccy: str) -> float:
    """Spread bid/ask della barra in pips (media open e close). Richiede colonne *_bid / *_ask."""
    o_sp = float(row["open_ask"] - row["open_bid"])
    c_sp = float(row["close_ask"] - row["close_bid"])
    avg_sp = (o_sp + c_sp) / 2.0
    return float(_price_diff_to_pips(avg_sp, quote_ccy))


def _fx_pnl_in_quote_currency(
    entry: float,
    exit_px: float,
    side: str,
    lots: float,
    contract_units: float = _FX_UNITS_PER_LOT,
) -> float:
    """Utile/perdita nella valuta di quotazione (prezzo = quotazione per 1 unità di base)."""
    if lots <= 0 or contract_units <= 0:
        return 0.0
    mult = lots * contract_units
    s = str(side).lower()
    if s == "buy":
        return float(mult * (exit_px - entry))
    return float(mult * (entry - exit_px))


def _pnl_quote_to_euro(
    pnl_quote: float,
    quote_ccy: str,
    norm_pair: str,
    ref_entry: float,
) -> tuple[float, str]:
    """Converte P&L dalla quotazione a EUR (ref_entry = prezzo ingresso del segnale quando utile)."""
    q = (quote_ccy or "USD").upper()
    if q == "EUR":
        return float(pnl_quote), "EUR (quotazione già in EUR)"
    if q == "USD":
        if norm_pair == "EURUSD" and ref_entry and ref_entry > 0:
            return float(pnl_quote / ref_entry), "USD→EUR con EURUSD ingresso"
        return float(pnl_quote / _EUR_USD_FALLBACK), f"USD→EUR fallback EURUSD={_EUR_USD_FALLBACK}"
    if q == "JPY":
        if norm_pair == "EURJPY" and ref_entry and ref_entry > 0:
            return float(pnl_quote / ref_entry), "JPY→EUR con EURJPY ingresso"
        return float(pnl_quote / _EUR_JPY_FALLBACK), f"JPY→EUR fallback EURJPY={_EUR_JPY_FALLBACK}"
    return float(pnl_quote / _EUR_USD_FALLBACK), f"{q}→EUR via USD fallback EURUSD={_EUR_USD_FALLBACK}"


def _iter_year_months(start: datetime, end: datetime):
    current = start.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    end_marker = end.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    while current <= end_marker:
        yield current.year, f"{current.month:02d}"
        if current.month == 12:
            current = current.replace(year=current.year + 1, month=1)
        else:
            current = current.replace(month=current.month + 1)


def _normalize_side_ohlc(df: pd.DataFrame, side: str) -> pd.DataFrame:
    """
    Normalizza DataFrame Bid/Ask con schemi variabili.
    Output: datetime, open_{side}, high_{side}, low_{side}, close_{side}
    """
    if df.empty:
        return pd.DataFrame(
            columns=[
                "datetime",
                f"open_{side}",
                f"high_{side}",
                f"low_{side}",
                f"close_{side}",
            ]
        )

    cols = list(df.columns)
    lower = {str(c).lower(): c for c in cols}

    dt_col = None
    for key in ("datetime", "date_time", "timestamp", "time", "date"):
        if key in lower:
            dt_col = lower[key]
            break
    if dt_col is None:
        dt_col = cols[0]

    def _pick(candidates: tuple[str, ...]) -> Any:
        for cand in candidates:
            if cand in lower:
                return lower[cand]
        return None

    open_col = _pick((f"open_{side}", f"{side}_open", "open"))
    high_col = _pick((f"high_{side}", f"{side}_high", "high"))
    low_col = _pick((f"low_{side}", f"{side}_low", "low"))
    close_col = _pick((f"close_{side}", f"{side}_close", "close"))

    if None in (open_col, high_col, low_col, close_col):
        non_dt = [c for c in cols if c != dt_col]
        if len(non_dt) < 4:
            raise ValueError(f"schema non valido: colonne insufficienti {cols}")
        # fallback posizionale: datetime + prime 4 colonne OHLC (ignora extra, es. volume)
        open_col, high_col, low_col, close_col = non_dt[:4]

    return pd.DataFrame(
        {
            "datetime": df[dt_col],
            f"open_{side}": df[open_col],
            f"high_{side}": df[high_col],
            f"low_{side}": df[low_col],
            f"close_{side}": df[close_col],
        }
    )


def _calculate_ema(series: pd.Series, length: int) -> pd.Series:
    length = max(1, int(length))
    return series.ewm(span=length, adjust=False).mean()


def _calculate_rsi(series: pd.Series, length: int) -> pd.Series:
    length = max(1, int(length))
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(alpha=1 / length, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / length, adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0, pd.NA)
    rsi = 100 - (100 / (1 + rs))
    return rsi.fillna(50.0)


def _calculate_atr(df: pd.DataFrame, length: int = 14) -> pd.Series:
    length = max(1, int(length))
    high = df["high_bid"]
    low = df["low_bid"]
    close = df["close_bid"]
    prev_close = close.shift(1)
    tr = pd.concat(
        [
            (high - low),
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    return tr.ewm(alpha=1 / length, adjust=False).mean()


def _calculate_di_plus_minus_adx_wilder(
    high: pd.Series,
    low: pd.Series,
    close: pd.Series,
    period: int,
) -> tuple[pd.Series, pd.Series, pd.Series]:
    """
    +DI, −DI e ADX in stile Wilder (0–100) su H,L,C.
    Usato con il filtro ADX quando `filterDi` è attivo (allineamento direzionale).
    """
    period = max(2, int(period))
    high = high.astype(float)
    low = low.astype(float)
    close = close.astype(float)

    up_move = high.diff()
    down_move = low.shift(1) - low
    plus_dm = up_move.where((up_move > down_move) & (up_move > 0), 0.0).fillna(0.0)
    minus_dm = down_move.where((down_move > up_move) & (down_move > 0), 0.0).fillna(0.0)

    prev_close = close.shift(1)
    tr = pd.concat(
        [
            high - low,
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)

    alpha = 1.0 / period
    tr_s = tr.ewm(alpha=alpha, adjust=False).mean()
    plus_s = plus_dm.ewm(alpha=alpha, adjust=False).mean()
    minus_s = minus_dm.ewm(alpha=alpha, adjust=False).mean()

    tr_safe = tr_s.replace(0, pd.NA)
    plus_di = (100.0 * plus_s / tr_safe).fillna(0.0).clip(lower=0.0, upper=100.0)
    minus_di = (100.0 * minus_s / tr_safe).fillna(0.0).clip(lower=0.0, upper=100.0)
    den = (plus_di + minus_di).replace(0, pd.NA)
    dx = (100.0 * (plus_di - minus_di).abs() / den).fillna(0.0).clip(lower=0.0, upper=100.0)
    adx = dx.ewm(alpha=alpha, adjust=False).mean().fillna(0.0).clip(lower=0.0, upper=100.0)
    return plus_di, minus_di, adx


def _calculate_macd_hist(series: pd.Series, fast: int, slow: int, signal: int) -> pd.Series:
    fast_ema = _calculate_ema(series, fast)
    slow_ema = _calculate_ema(series, slow)
    macd_line = fast_ema - slow_ema
    signal_line = _calculate_ema(macd_line, signal)
    return macd_line - signal_line


def _bollinger(close: pd.Series, length: int, std_mult: float) -> tuple[pd.Series, pd.Series]:
    length = max(1, int(length))
    ma = close.rolling(window=length).mean()
    std = close.rolling(window=length).std()
    return ma + (std_mult * std), ma - (std_mult * std)


def _strategy_with_defaults(raw_doc: dict[str, Any]) -> dict[str, Any]:
    base = {
        "timeframes": {
            "operativo": "15m",
            "medio": "4h",
            "lungo": "1d",
            "test": "1m",
        },
        "indicators": {
            "emaLong": {"enabled": True, "length": 200, "weight": 25, "timeframe": "operativo"},
            "emaShort": {"enabled": False, "length": 50, "weight": 15, "timeframe": "operativo"},
            "smaSignal": {"enabled": False, "length": 20, "weight": 10, "timeframe": "operativo"},
            "rsi": {
                "enabled": True,
                "length": 14,
                "weight": 15,
                "oversold": 30,
                "overbought": 70,
                "timeframe": "operativo",
            },
            "macd": {
                "enabled": False,
                "fast": 12,
                "slow": 26,
                "signal": 9,
                "weight": 10,
                "timeframe": "operativo",
            },
            "pivot": {"enabled": False, "type": "Standard", "weight": 10, "timeframe": "operativo"},
            "adrScore": {"enabled": False, "length": 14, "weight": 15, "timeframe": "operativo"},
        },
        "filters": {
            "superTrend": {"enabled": False, "period": 10, "multiplier": 3.0, "timeframe": "operativo"},
            "bollinger": {"enabled": False, "length": 20, "std": 2.0, "timeframe": "operativo"},
            "adx": {"enabled": False, "period": 14, "threshold": 20.0, "filterDi": False, "timeframe": "operativo"},
            "maxAdrExtension": 0.85,
            "minAtrLevel": 0.0005,
            "tradingSession": {"enabled": False, "start": "08:00", "end": "20:00"},
            "maxSpreadAllowed": 3.0,
        },
        "exitRules": {
            "maxSimultaneousTrades": 3,
            "activationScore": 55,
            "slAtrMult": 2.0,
            "tpAtrMult": 4.0,
            "minLotPerTrade": 0.01,
            "breakEven": {"active": False, "triggerAtrMult": 1.0, "lockAtrMult": 0.1},
            "trailingStop": {"active": True, "activationAtrMult": 1.5, "stepAtrMult": 1.0},
        },
    }
    strategy = dict(base)
    for section in ("timeframes", "indicators", "filters", "exitRules"):
        incoming = raw_doc.get(section)
        if isinstance(incoming, dict):
            merged = dict(base[section])
            for k, v in incoming.items():
                if isinstance(v, dict) and isinstance(merged.get(k), dict):
                    sub = dict(merged[k])
                    sub.update(v)
                    merged[k] = sub
                else:
                    merged[k] = v
            strategy[section] = merged
    le_out: dict[str, Any] = {"enabled": True, "intervalMinutes": 5}
    le_in = raw_doc.get("liveSignalEvaluation")
    if isinstance(le_in, dict):
        if "enabled" in le_in:
            le_out["enabled"] = bool(le_in["enabled"])
        raw_m = le_in.get("intervalMinutes")
        if raw_m is not None:
            try:
                le_out["intervalMinutes"] = int(max(2, min(120, int(raw_m))))
            except (TypeError, ValueError):
                pass
    strategy["liveSignalEvaluation"] = le_out
    return strategy


def _timeframe_df_for_indicator(
    df_by_role: dict[str, pd.DataFrame],
    cfg: dict[str, Any],
    fallback_role: str = "operativo",
) -> pd.DataFrame:
    role = str(cfg.get("timeframe") or fallback_role)
    return df_by_role.get(role) if role in df_by_role else df_by_role.get(fallback_role, pd.DataFrame())


def _compute_indicator_snapshot(
    df_by_role: dict[str, pd.DataFrame],
    strategy: dict[str, Any],
) -> tuple[dict[str, Any], list[str]]:
    logs: list[str] = []
    indicators_out: dict[str, Any] = {}
    ind_cfg = strategy.get("indicators", {})
    filt_cfg = strategy.get("filters", {})

    for name in ("emaLong", "emaShort", "smaSignal", "rsi", "macd", "pivot", "adrScore"):
        cfg = ind_cfg.get(name, {})
        if not cfg.get("enabled", False):
            indicators_out[name] = {"enabled": False}
            continue
        df = _timeframe_df_for_indicator(df_by_role, cfg)
        if df is None or df.empty:
            indicators_out[name] = {"enabled": True, "value": None, "reason": "no_data"}
            logs.append(f"indicatore {name}: no data sul timeframe {cfg.get('timeframe')}")
            continue
        close = (df["close_bid"] + df["close_ask"]) / 2.0
        value: Any = None
        if name == "emaLong":
            value = float(_calculate_ema(close, int(cfg.get("length", 200))).iloc[-1])
        elif name == "emaShort":
            value = float(_calculate_ema(close, int(cfg.get("length", 50))).iloc[-1])
        elif name == "smaSignal":
            value = float(close.rolling(window=max(1, int(cfg.get("length", 20)))).mean().iloc[-1])
        elif name == "rsi":
            value = float(_calculate_rsi(close, int(cfg.get("length", 14))).iloc[-1])
        elif name == "macd":
            value = float(
                _calculate_macd_hist(
                    close,
                    int(cfg.get("fast", 12)),
                    int(cfg.get("slow", 26)),
                    int(cfg.get("signal", 9)),
                ).iloc[-1]
            )
        elif name == "pivot":
            if len(df) >= 2:
                prev = df.iloc[-2]
                value = float((prev["high_bid"] + prev["low_bid"] + prev["close_bid"]) / 3.0)
        elif name == "adrScore":
            atr = _calculate_atr(df, int(cfg.get("length", 14))).iloc[-1]
            avg_price = float(close.mean()) if len(close) else 0.0
            value = float(min((atr / (avg_price * 0.01)) if avg_price > 0 else 0.0, 1.0))
        indicators_out[name] = {
            "enabled": True,
            "timeframe": cfg.get("timeframe"),
            "value": value,
            "weight": cfg.get("weight"),
        }

    # Filtri con timeframe dedicato
    for fname in ("superTrend", "bollinger", "adx"):
        cfg = filt_cfg.get(fname, {})
        if not cfg.get("enabled", False):
            continue
        df = _timeframe_df_for_indicator(df_by_role, cfg)
        if df is None or df.empty:
            logs.append(f"filtro {fname}: no data sul timeframe {cfg.get('timeframe')}")
            continue
        close = (df["close_bid"] + df["close_ask"]) / 2.0
        if fname == "bollinger":
            upper, lower = _bollinger(close, int(cfg.get("length", 20)), float(cfg.get("std", 2.0)))
            indicators_out["filter_bollinger"] = {
                "timeframe": cfg.get("timeframe"),
                "upper": float(upper.iloc[-1]),
                "lower": float(lower.iloc[-1]),
                "close": float(close.iloc[-1]),
            }
        elif fname == "adx":
            period = int(cfg.get("period", 14))
            atr = _calculate_atr(df, period)
            # Proxy per soglia: ATR/close×10000 (scala storica app); con filterDi anche +DI/−DI Wilder.
            adx_like = ((atr / close.replace(0, pd.NA)) * 10000).fillna(0.0)
            adx_payload: dict[str, Any] = {
                "timeframe": cfg.get("timeframe"),
                "value": float(adx_like.iloc[-1]),
                "threshold": float(cfg.get("threshold", 20.0)),
                "filterDi": bool(cfg.get("filterDi", False)),
            }
            if bool(cfg.get("filterDi")):
                di_p, di_m, adx_w = _calculate_di_plus_minus_adx_wilder(
                    df["high_bid"].astype(float),
                    df["low_bid"].astype(float),
                    close.astype(float),
                    period,
                )
                adx_payload["diPlus"] = float(di_p.iloc[-1])
                adx_payload["diMinus"] = float(di_m.iloc[-1])
                adx_payload["adxWilder"] = float(adx_w.iloc[-1])
            indicators_out["filter_adx"] = adx_payload
        elif fname == "superTrend":
            ema = _calculate_ema(close, int(cfg.get("period", 10)))
            direction = 1 if float(close.iloc[-1]) >= float(ema.iloc[-1]) else -1
            indicators_out["filter_superTrend"] = {
                "timeframe": cfg.get("timeframe"),
                "direction": direction,
            }

    return indicators_out, logs


def _prepare_role_feature_frame(
    role: str,
    df: pd.DataFrame,
    strategy: dict[str, Any],
    norm_pair: str,
) -> pd.DataFrame:
    out = pd.DataFrame()
    if df is None or df.empty:
        return out
    fx_sp = _split_fx_pair(_normalize_pair_symbols(norm_pair))
    quote_ccy = fx_sp[1] if fx_sp else "USD"
    pip_sz = _pip_size_for_quote(quote_ccy)
    out["datetime"] = pd.to_datetime(df["datetime"], utc=True)
    out["close_mid"] = (df["close_bid"] + df["close_ask"]) / 2.0
    out["open_mid"] = (df["open_bid"] + df["open_ask"]) / 2.0
    out["high_mid"] = (df["high_bid"] + df["high_ask"]) / 2.0
    out["low_mid"] = (df["low_bid"] + df["low_ask"]) / 2.0
    # Spread in pips coerente con pip JPY (0,01) vs majors (0,0001); prima era fisso *10000 → JPY falsamente ~100×.
    spread_price = df["close_ask"] - df["close_bid"]
    out["spread_pips"] = spread_price / pip_sz if pip_sz else spread_price * 10000.0
    out["atr14"] = _calculate_atr(df, 14)

    indicators_cfg = strategy.get("indicators", {})
    filters_cfg = strategy.get("filters", {})

    def _enabled_on_role(name: str) -> dict[str, Any] | None:
        cfg = indicators_cfg.get(name, {})
        if cfg.get("enabled") and str(cfg.get("timeframe", "operativo")) == role:
            return cfg
        return None

    ema_long_cfg = _enabled_on_role("emaLong")
    if ema_long_cfg:
        out["emaLong"] = _calculate_ema(out["close_mid"], int(ema_long_cfg.get("length", 200)))

    ema_short_cfg = _enabled_on_role("emaShort")
    if ema_short_cfg:
        out["emaShort"] = _calculate_ema(out["close_mid"], int(ema_short_cfg.get("length", 50)))

    sma_cfg = _enabled_on_role("smaSignal")
    if sma_cfg:
        out["smaSignal"] = out["close_mid"].rolling(window=max(1, int(sma_cfg.get("length", 20)))).mean()

    rsi_cfg = _enabled_on_role("rsi")
    if rsi_cfg:
        out["rsi"] = _calculate_rsi(out["close_mid"], int(rsi_cfg.get("length", 14)))

    macd_cfg = _enabled_on_role("macd")
    if macd_cfg:
        out["macd_hist"] = _calculate_macd_hist(
            out["close_mid"],
            int(macd_cfg.get("fast", 12)),
            int(macd_cfg.get("slow", 26)),
            int(macd_cfg.get("signal", 9)),
        )

    pivot_cfg = _enabled_on_role("pivot")
    if pivot_cfg:
        out["pivot"] = ((df["high_bid"] + df["low_bid"] + df["close_bid"]) / 3.0).shift(1)

    adr_cfg = _enabled_on_role("adrScore")
    if adr_cfg:
        atr_len = _calculate_atr(df, int(adr_cfg.get("length", 14)))
        avg_price = out["close_mid"].rolling(window=max(1, int(adr_cfg.get("length", 14)))).mean()
        out["adrScore"] = ((atr_len / (avg_price * 0.01)).clip(lower=0)).fillna(0).clip(upper=1.0)

    st_cfg = filters_cfg.get("superTrend", {})
    if st_cfg.get("enabled") and str(st_cfg.get("timeframe", "operativo")) == role:
        st_period = int(st_cfg.get("period", 10))
        ema_base = _calculate_ema(out["close_mid"], st_period)
        out["superTrendDir"] = (out["close_mid"] >= ema_base).astype(int).replace({0: -1})

    bb_cfg = filters_cfg.get("bollinger", {})
    if bb_cfg.get("enabled") and str(bb_cfg.get("timeframe", "operativo")) == role:
        upper, lower = _bollinger(
            out["close_mid"],
            int(bb_cfg.get("length", 20)),
            float(bb_cfg.get("std", 2.0)),
        )
        out["bb_upper"] = upper
        out["bb_lower"] = lower

    adx_cfg = filters_cfg.get("adx", {})
    if adx_cfg.get("enabled") and str(adx_cfg.get("timeframe", "operativo")) == role:
        adx_period = int(adx_cfg.get("period", 14))
        atr_period = _calculate_atr(df, adx_period)
        out["adx_like"] = ((atr_period / out["close_mid"].replace(0, pd.NA)) * 10000).fillna(0.0)
        if bool(adx_cfg.get("filterDi")):
            di_p, di_m, adx_w = _calculate_di_plus_minus_adx_wilder(
                df["high_bid"].astype(float),
                df["low_bid"].astype(float),
                out["close_mid"].astype(float),
                adx_period,
            )
            out["di_plus"] = di_p
            out["di_minus"] = di_m
            out["adx_wilder"] = adx_w

    return out.sort_values("datetime").reset_index(drop=True)


def _align_role_frames(
    df_by_role: dict[str, pd.DataFrame],
    strategy: dict[str, Any],
    norm_pair: str,
) -> pd.DataFrame:
    op = _prepare_role_feature_frame(
        "operativo",
        df_by_role.get("operativo", pd.DataFrame()),
        strategy,
        norm_pair,
    )
    if op.empty:
        return pd.DataFrame()
    aligned = op.rename(columns={c: f"operativo__{c}" for c in op.columns if c != "datetime"})
    for role in ("medio", "lungo", "test"):
        role_df = _prepare_role_feature_frame(
            role,
            df_by_role.get(role, pd.DataFrame()),
            strategy,
            norm_pair,
        )
        if role_df.empty:
            continue
        role_df = role_df.rename(columns={c: f"{role}__{c}" for c in role_df.columns if c != "datetime"})
        aligned = pd.merge_asof(
            aligned.sort_values("datetime"),
            role_df.sort_values("datetime"),
            on="datetime",
            direction="backward",
        )
    return aligned.reset_index(drop=True)


def _safe_float(value: Any) -> float | None:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _sl_price_moved(old_sl: float, new_sl: float, entry_price: float) -> bool:
    eps = max(1e-9, abs(float(entry_price)) * 1e-8)
    return abs(float(new_sl) - float(old_sl)) > eps


def _int_from_firestore_field(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return value
    try:
        return int(float(str(value).replace(",", ".")))
    except (TypeError, ValueError):
        return 0


def _close_mid_for_role(decision_row: pd.Series, role: str) -> float | None:
    """Close mid della barra del ruolo TF (operativo/medio/lungo/test) sulla riga allineata."""
    r = str(role or "operativo")
    return _safe_float(decision_row.get(f"{r}__close_mid"))


def _exit_rules_max_simultaneous(exit_cfg: Any) -> int:
    """Allineato alla simulazione backtest: <1 o assente → effettivamente illimitato."""
    max_raw = exit_cfg.get("maxSimultaneousTrades") if isinstance(exit_cfg, dict) else None
    try:
        max_sim = int(float(max_raw)) if max_raw is not None else 10**9
    except (TypeError, ValueError):
        max_sim = 10**9
    if max_sim < 1:
        max_sim = 10**9
    return max_sim


def _signal_entry_atr(sig: dict[str, Any], exit_cfg: dict[str, Any]) -> float | None:
    """ATR del timeframe operativo alla voce (come SL/TP), in unità di prezzo."""
    snap = sig.get("indicatorsSnapshot")
    if isinstance(snap, dict):
        flt = snap.get("filters")
        if isinstance(flt, dict):
            v = _safe_float(flt.get("atrOperativo"))
            if v is not None and v > 0:
                return float(v)
    sl_d = _safe_float(sig.get("slDistance"))
    sl_m = _safe_float(exit_cfg.get("slAtrMult")) if isinstance(exit_cfg, dict) else None
    if sl_m is None or sl_m <= 0:
        sl_m = 2.0
    if sl_d is not None and sl_d > 0:
        return float(sl_d / sl_m)
    return None


def _break_even_atr_mults(be_cfg: dict[str, Any]) -> tuple[float, float]:
    """
    Break-even: soglia e lock come moltiplicatori dell'ATR alla voce (distanze in prezzo in simulazione).
    Preferisce `triggerAtrMult` / `lockAtrMult`; altrimenti da legacy `triggerPips` / `lockProfit`
    con euristica tipica (÷15 e ÷10) per avvicinare i default storici (15 pips, 1 pip).
    """
    if not isinstance(be_cfg, dict):
        return 1.0, 0.1
    t_m = _safe_float(be_cfg.get("triggerAtrMult"))
    l_m = _safe_float(be_cfg.get("lockAtrMult"))
    if t_m is not None and t_m > 0 and l_m is not None and l_m > 0:
        return max(0.01, float(t_m)), max(0.001, float(l_m))
    try:
        tp = float(be_cfg.get("triggerPips", 15.0) or 15.0)
    except (TypeError, ValueError):
        tp = 15.0
    try:
        lp = float(be_cfg.get("lockProfit", 1.0) or 1.0)
    except (TypeError, ValueError):
        lp = 1.0
    return max(0.01, tp / 15.0), max(0.001, lp / 10.0)


def _trailing_stop_atr_mults(tr_cfg: dict[str, Any]) -> tuple[float, float]:
    """
    Moltiplicatori dell'ATR alla voce per trailing: soglia su profitto massimo da picco e passo minimo
    (distanze in prezzo nella simulazione 1m a livelli da picco/trough).
    Preferisce `activationAtrMult` / `stepAtrMult`; se assenti, da legacy `activationPips` /
    `stepPips` (pips fissi) con euristica pips/20 → moltiplicatore ATR tipico su FX major.
    """
    if not isinstance(tr_cfg, dict):
        return 1.5, 1.0
    a_m = _safe_float(tr_cfg.get("activationAtrMult"))
    s_m = _safe_float(tr_cfg.get("stepAtrMult"))
    if a_m is not None and a_m > 0 and s_m is not None and s_m > 0:
        return max(0.05, float(a_m)), max(0.05, float(s_m))
    try:
        ap = float(tr_cfg.get("activationPips", 30.0) or 30.0)
    except (TypeError, ValueError):
        ap = 30.0
    try:
        sp = float(tr_cfg.get("stepPips", 20.0) or 20.0)
    except (TypeError, ValueError):
        sp = 20.0
    return max(0.05, ap / 20.0), max(0.05, sp / 20.0)


def _signal_firestore_doc_is_open(data: dict[str, Any]) -> bool:
    """Posizione ancora aperta: nessuna uscita registrata (camelCase o snake)."""
    if data.get("exit_time") is not None or data.get("exitTime") is not None:
        return False
    if data.get("exit_price") is not None or data.get("exitPrice") is not None:
        return False
    return True


def _count_open_live_signals(
    uid: str,
    pair: str,
    *,
    exclude_doc_id: str | None = None,
    limit_scan: int = 400,
) -> int:
    """
    Conta segnali live ancora aperti (stesso utente e coppia) su `signals`.
    isTest==True viene ignorato (in genere i test stanno in test_signals).
    """
    col = get_db().collection("signals")
    q = (
        col.where("userId", "==", uid)
        .where("pair", "==", pair.upper())
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit_scan)
    )
    n = 0
    for doc in q.stream():
        if exclude_doc_id and doc.id == exclude_doc_id:
            continue
        data = doc.to_dict() or {}
        if data.get("isTest") is True:
            continue
        if _signal_firestore_doc_is_open(data):
            n += 1
    return n


def _parse_hhmm(hhmm: str) -> tuple[int, int]:
    h, m = (hhmm or "00:00").split(":")
    return int(h), int(m)


def _in_trading_session(ts: pd.Timestamp, start_hhmm: str, end_hhmm: str) -> bool:
    sh, sm = _parse_hhmm(start_hhmm)
    eh, em = _parse_hhmm(end_hhmm)
    mins = ts.hour * 60 + ts.minute
    start = sh * 60 + sm
    end = eh * 60 + em
    if start <= end:
        return start <= mins <= end
    return mins >= start or mins <= end


def _generate_test_signals(
    uid: str,
    pair: str,
    aligned: pd.DataFrame,
    strategy: dict[str, Any],
    *,
    is_test: bool = True,
) -> tuple[list[dict[str, Any]], list[str]]:
    logs: list[str] = []
    signals: list[dict[str, Any]] = []
    if aligned.empty:
        logs.append("generazione segnali: dataframe allineato vuoto")
        return signals, logs

    indicators_cfg = strategy.get("indicators", {})
    filters_cfg = strategy.get("filters", {})
    exit_cfg = strategy.get("exitRules", {})
    activation_score = float(exit_cfg.get("activationScore", 55))
    sl_mult = float(exit_cfg.get("slAtrMult", 2.0))
    tp_mult = float(exit_cfg.get("tpAtrMult", 4.0))
    min_lot = float(exit_cfg.get("minLotPerTrade", 0.01))
    if min_lot < 0.01:
        min_lot = 0.01
    pair_norm = _normalize_pair_symbols(pair)
    fx_split = _split_fx_pair(pair_norm)
    quote_ccy = fx_split[1] if fx_split else "USD"
    max_spread = float(filters_cfg.get("maxSpreadAllowed", 9999.0))
    min_atr_level = float(filters_cfg.get("minAtrLevel", 0.0))
    max_adr_ext = float(filters_cfg.get("maxAdrExtension", 9999.0))
    sess_cfg = filters_cfg.get("tradingSession", {})
    session_enabled = bool(sess_cfg.get("enabled", False))
    session_start = str(sess_cfg.get("start", "00:00"))
    session_end = str(sess_cfg.get("end", "23:59"))

    prev_score = 0.0
    # Anti-lookahead: decisione su barra precedente (i-1), ingresso su barra corrente (i).
    for i in range(1, len(aligned)):
        decision_row = aligned.iloc[i - 1]
        exec_row = aligned.iloc[i]

        close_op = _safe_float(decision_row.get("operativo__close_mid"))
        atr_op = _safe_float(decision_row.get("operativo__atr14"))
        spread_pips = _safe_float(decision_row.get("operativo__spread_pips")) or 0.0
        ts = exec_row.get("datetime")
        entry_open = _safe_float(exec_row.get("operativo__open_mid"))
        if close_op is None or atr_op is None or atr_op <= 0:
            continue
        if session_enabled and isinstance(ts, pd.Timestamp) and not _in_trading_session(ts, session_start, session_end):
            continue

        score_sum = 0.0
        weight_sum = 0.0
        indicator_values: dict[str, Any] = {}

        def _role_col(cfg: dict[str, Any], col: str) -> Any:
            role = str(cfg.get("timeframe", "operativo"))
            return decision_row.get(f"{role}__{col}")

        # EMA Long (close e ATR sullo stesso TF dell'indicatore, es. medio__close_mid vs medio__emaLong)
        cfg = indicators_cfg.get("emaLong", {})
        if cfg.get("enabled", False):
            ema_tf = str(cfg.get("timeframe", "operativo"))
            ema_val = _safe_float(_role_col(cfg, "emaLong"))
            atr_val = _safe_float(_role_col(cfg, "atr14")) or atr_op
            close_tf = _close_mid_for_role(decision_row, ema_tf) or close_op
            weight = float(cfg.get("weight", 25))
            if ema_val is not None and atr_val > 0:
                norm = max(-1.0, min(1.0, ((close_tf - ema_val) / atr_val) / 3.0))
                contrib = (norm + 1.0) / 2.0
                score_sum += contrib * weight
                weight_sum += weight
            indicator_values["emaLong"] = ema_val

        # EMA Short
        cfg = indicators_cfg.get("emaShort", {})
        if cfg.get("enabled", False):
            short_val = _safe_float(_role_col(cfg, "emaShort"))
            long_ref = _safe_float(_role_col(cfg, "emaLong"))
            weight = float(cfg.get("weight", 15))
            if short_val is not None and long_ref is not None:
                contrib = 1.0 if short_val > long_ref else 0.0
                score_sum += contrib * weight
                weight_sum += weight
            indicator_values["emaShort"] = short_val

        # SMA Signal
        cfg = indicators_cfg.get("smaSignal", {})
        if cfg.get("enabled", False):
            sma_val = _safe_float(_role_col(cfg, "smaSignal"))
            weight = float(cfg.get("weight", 10))
            if sma_val is not None:
                contrib = 1.0 if close_op > sma_val else 0.0
                score_sum += contrib * weight
                weight_sum += weight
            indicator_values["smaSignal"] = sma_val

        # RSI
        cfg = indicators_cfg.get("rsi", {})
        if cfg.get("enabled", False):
            rsi_val = _safe_float(_role_col(cfg, "rsi"))
            weight = float(cfg.get("weight", 15))
            if rsi_val is not None:
                contrib = max(0.0, min(1.0, rsi_val / 100.0))
                score_sum += contrib * weight
                weight_sum += weight
            indicator_values["rsi"] = rsi_val

        # MACD
        cfg = indicators_cfg.get("macd", {})
        if cfg.get("enabled", False):
            macd_val = _safe_float(_role_col(cfg, "macd_hist"))
            weight = float(cfg.get("weight", 10))
            if macd_val is not None:
                norm = max(-1.0, min(1.0, macd_val / 0.001))
                contrib = (norm + 1.0) / 2.0
                score_sum += contrib * weight
                weight_sum += weight
            indicator_values["macd_hist"] = macd_val

        # Pivot
        cfg = indicators_cfg.get("pivot", {})
        if cfg.get("enabled", False):
            piv_val = _safe_float(_role_col(cfg, "pivot"))
            weight = float(cfg.get("weight", 10))
            if piv_val is not None:
                contrib = 1.0 if close_op > piv_val else 0.0
                score_sum += contrib * weight
                weight_sum += weight
            indicator_values["pivot"] = piv_val

        # ADR Score
        cfg = indicators_cfg.get("adrScore", {})
        adr_val = None
        if cfg.get("enabled", False):
            adr_val = _safe_float(_role_col(cfg, "adrScore"))
            weight = float(cfg.get("weight", 15))
            if adr_val is not None:
                contrib = max(0.0, min(1.0, adr_val))
                score_sum += contrib * weight
                weight_sum += weight
            indicator_values["adrScore"] = adr_val

        score = (score_sum / weight_sum) * 100.0 if weight_sum > 0 else 50.0

        # Filtri
        adx_cfg = filters_cfg.get("adx", {})
        adx_val = None
        if adx_cfg.get("enabled", False):
            adx_val = _safe_float(decision_row.get(f"{adx_cfg.get('timeframe', 'operativo')}__adx_like"))
            if adx_val is not None and adx_val < float(adx_cfg.get("threshold", 20.0)):
                score *= 0.7

        st_cfg = filters_cfg.get("superTrend", {})
        st_dir = None
        if st_cfg.get("enabled", False):
            st_dir = _safe_float(decision_row.get(f"{st_cfg.get('timeframe', 'operativo')}__superTrendDir"))

        bb_cfg = filters_cfg.get("bollinger", {})
        bb_upper = bb_lower = None
        if bb_cfg.get("enabled", False):
            tf = str(bb_cfg.get("timeframe", "operativo"))
            bb_upper = _safe_float(decision_row.get(f"{tf}__bb_upper"))
            bb_lower = _safe_float(decision_row.get(f"{tf}__bb_lower"))
            close_tf = _safe_float(decision_row.get(f"{tf}__close_mid")) or close_op
            if bb_upper is not None and bb_lower is not None:
                if close_tf > bb_upper * 1.02 or close_tf < bb_lower * 0.98:
                    score *= 0.8

        if spread_pips > max_spread:
            score *= 0.2
        if atr_op < min_atr_level:
            score *= 0.5
        if adr_val is not None and adr_val > max_adr_ext:
            score *= 0.6

        score = max(0.0, min(100.0, score))
        crossed_up = prev_score < activation_score <= score
        prev_score = score
        if not crossed_up:
            continue

        entry_price = entry_open if entry_open is not None else close_op
        long_ref = indicator_values.get("emaLong")
        short_ref = indicator_values.get("emaShort")
        direction = "buy"
        if short_ref is not None and long_ref is not None:
            direction = "buy" if short_ref > long_ref else "sell"
        elif long_ref is not None:
            ema_long_tf = str(indicators_cfg.get("emaLong", {}).get("timeframe", "operativo"))
            dc_long = _close_mid_for_role(decision_row, ema_long_tf) or close_op
            direction = "buy" if dc_long >= float(long_ref) else "sell"
        if st_dir is not None and st_dir < 0 and direction == "buy":
            direction = "sell"

        # Filtro DI (con ADX): richiede +DI > −DI per i long e −DI > +DI per gli short sulla barra decisione.
        if adx_cfg.get("enabled", False) and bool(adx_cfg.get("filterDi")):
            adx_tf = str(adx_cfg.get("timeframe", "operativo"))
            di_p = _safe_float(decision_row.get(f"{adx_tf}__di_plus"))
            di_m = _safe_float(decision_row.get(f"{adx_tf}__di_minus"))
            if di_p is not None and di_m is not None:
                if direction == "buy" and di_p <= di_m:
                    continue
                if direction == "sell" and di_m <= di_p:
                    continue

        sl_distance = atr_op * sl_mult
        tp_distance = atr_op * tp_mult
        if direction == "buy":
            stop_loss = entry_price - sl_distance
            take_profit = entry_price + tp_distance
        else:
            stop_loss = entry_price + sl_distance
            take_profit = entry_price - tp_distance

        adx_tf_snap = str(adx_cfg.get("timeframe", "operativo"))
        di_snap_plus = (
            _safe_float(decision_row.get(f"{adx_tf_snap}__di_plus"))
            if adx_cfg.get("enabled", False) and bool(adx_cfg.get("filterDi"))
            else None
        )
        di_snap_minus = (
            _safe_float(decision_row.get(f"{adx_tf_snap}__di_minus"))
            if adx_cfg.get("enabled", False) and bool(adx_cfg.get("filterDi"))
            else None
        )

        signal_payload = {
            "userId": uid,
            "pair": pair.upper(),
            "type": direction,
            "score": float(score),
            "timestamp": ts.to_pydatetime() if isinstance(ts, pd.Timestamp) else datetime.utcnow(),
            "entryPrice": float(entry_price),
            "stopLoss": float(stop_loss),
            "takeProfit": float(take_profit),
            "indicatorsSnapshot": {
                "indicators": indicator_values,
                "filters": {
                    "adx": adx_val,
                    "diPlus": di_snap_plus,
                    "diMinus": di_snap_minus,
                    "superTrendDir": st_dir,
                    "bbUpper": bb_upper,
                    "bbLower": bb_lower,
                    "spreadPips": spread_pips,
                    "atrOperativo": atr_op,
                    "decisionTimestamp": (
                        decision_row.get("datetime").to_pydatetime()
                        if isinstance(decision_row.get("datetime"), pd.Timestamp)
                        else decision_row.get("datetime")
                    ),
                },
                "activationScore": activation_score,
            },
            "isProcessed": False,
            "isTest": is_test,
            "createdAt": firestore.SERVER_TIMESTAMP,
            "strategy": {
                "timeframes": strategy.get("timeframes", {}),
                "indicators": strategy.get("indicators", {}),
                "filters": strategy.get("filters", {}),
                "exitRules": strategy.get("exitRules", {}),
            },
            "slDistance": float(sl_distance),
            "tpDistance": float(tp_distance),
            "minLotPerTrade": float(min_lot),
            "fxContractUnitsPerLot": float(_FX_UNITS_PER_LOT),
            "quoteCurrency": quote_ccy,
            "accountReportCurrency": "EUR",
            "stopLossAdjustmentCount": 0,
        }
        signals.append(signal_payload)

    logs.append(f"segnali generati: {len(signals)}")
    return signals, logs


def _replace_test_signals(
    uid: str,
    pair: str,
    start_dt: datetime,
    end_dt: datetime,
    signals: list[dict[str, Any]],
) -> int:
    col = get_db().collection("test_signals")
    start_ts = _to_utc_timestamp(start_dt)
    end_ts = _to_utc_timestamp(end_dt)
    old_docs = (
        col.where("userId", "==", uid)
        .where("pair", "==", pair.upper())
        .where("isTest", "==", True)
        .stream()
    )
    to_delete = []
    for doc in old_docs:
        data = doc.to_dict() or {}
        ts = data.get("timestamp")
        if ts is None:
            continue
        try:
            ts_utc = _to_utc_timestamp(ts)
        except Exception:
            continue
        if start_ts <= ts_utc <= end_ts:
            to_delete.append(doc.reference)
    for ref in to_delete:
        ref.delete()

    for sig in signals:
        col.document().set(sig)
    return len(signals)


def _simulate_signal_closures_1m(
    signals: list[dict[str, Any]],
    df_1m: pd.DataFrame,
    exit_cfg: dict[str, Any],
    *,
    progress_uid: str | None = None,
    progress_pair_upper: str | None = None,
) -> tuple[list[dict[str, Any]], list[str]]:
    logs: list[str] = []
    if not signals:
        return signals, logs
    if df_1m is None or df_1m.empty:
        logs.append("simulazione uscite 1M: nessun dato disponibile")
        for sig in signals:
            sig["exit_reason"] = "no_data_1m"
            sig["realized_pips"] = 0.0
            sig["profit_quote_currency"] = 0.0
            sig["realized_pnl_eur"] = 0.0
            sig["pnl_conversion_note"] = "no_data"
            sig["spread_entry_pips"] = 0.0
            sig["spread_exit_pips"] = 0.0
            sig["spread_round_trip_pips"] = 0.0
            sig["spread_paid_eur"] = 0.0
        return signals, logs

    df = df_1m.copy()
    df["datetime"] = pd.to_datetime(df["datetime"], utc=True)
    df = df.sort_values("datetime").reset_index(drop=True)

    # Viste NumPy: evita iterrows e filtri booleani O(n) per ogni segnale.
    dt_ns = df["datetime"].to_numpy(dtype="datetime64[ns]").astype(np.int64, copy=False)
    hb = df["high_bid"].to_numpy(dtype=np.float64, copy=False)
    lb = df["low_bid"].to_numpy(dtype=np.float64, copy=False)
    ha = df["high_ask"].to_numpy(dtype=np.float64, copy=False)
    la = df["low_ask"].to_numpy(dtype=np.float64, copy=False)
    cb = df["close_bid"].to_numpy(dtype=np.float64, copy=False)
    ca = df["close_ask"].to_numpy(dtype=np.float64, copy=False)
    n_bars = int(len(df))

    be_cfg = exit_cfg.get("breakEven", {}) if isinstance(exit_cfg, dict) else {}
    tr_cfg = exit_cfg.get("trailingStop", {}) if isinstance(exit_cfg, dict) else {}
    be_active = bool(be_cfg.get("active", False))
    be_trigger_mult, be_lock_mult = _break_even_atr_mults(be_cfg)
    tr_active = bool(tr_cfg.get("active", False))
    tr_act_mult, tr_step_mult = _trailing_stop_atr_mults(tr_cfg)

    max_sim = _exit_rules_max_simultaneous(exit_cfg)

    ordered_idx = sorted(
        range(len(signals)),
        key=lambda i: _to_utc_timestamp(signals[i].get("timestamp")),
    )
    total_sig_candidates = len(ordered_idx)
    prog: dict[str, Any] | None = None
    if progress_uid and progress_pair_upper:
        prog = {
            "uid": progress_uid,
            "pair": progress_pair_upper,
            "last": 0.0,
            "interval": 1.15,
        }
        _simulate_1m_progress_maybe(
            prog,
            f"Simulazione 1m: avvio su {total_sig_candidates} segnali candidati…",
            force=True,
        )

    def _attach_pnl(sig: dict[str, Any], entry_px: float, exit_px: float) -> None:
        pair_n = _normalize_pair_symbols(str(sig.get("pair", "")))
        sp = _split_fx_pair(pair_n)
        q_ccy = str(sig.get("quoteCurrency") or (sp[1] if sp else "USD"))
        pip_sz = _pip_size_for_quote(q_ccy)
        lots = float(sig.get("minLotPerTrade") or exit_cfg.get("minLotPerTrade", 0.01))
        if lots < 0.01:
            lots = 0.01
        contract = float(sig.get("fxContractUnitsPerLot") or _FX_UNITS_PER_LOT)
        if str(sig.get("type", "buy")).lower() == "buy":
            sig["realized_pips"] = float(_price_diff_to_pips(exit_px - entry_px, q_ccy))
        else:
            sig["realized_pips"] = float(_price_diff_to_pips(entry_px - exit_px, q_ccy))
        rp = float(sig["realized_pips"])
        # Stessa identità del movimento prezzo: evita disallineamenti pips ↔ P&L.
        pnl_q = float(lots * contract * rp * pip_sz)
        pnl_chk = _fx_pnl_in_quote_currency(entry_px, exit_px, str(sig.get("type", "buy")), lots, contract)
        if abs(pnl_q - pnl_chk) > 1e-6:
            _logger.warning(
                "run_backtest pnl/pips check pair=%s rp=%s pnl_from_pips=%s pnl_from_prices=%s",
                pair_n,
                rp,
                pnl_q,
                pnl_chk,
            )
        pnl_eur, note = _pnl_quote_to_euro(pnl_q, q_ccy, pair_n, entry_px)
        sig["profit_quote_currency"] = float(pnl_q)
        sig["quote_currency"] = q_ccy
        sig["realized_pnl_eur"] = float(pnl_eur)
        sig["pnl_conversion_note"] = (
            f"{note}; P&L {q_ccy} = minLot×{contract:.0f}×pips×pip_size ({rp} pips)."
        )

    def _attach_spread(
        sig: dict[str, Any],
        entry_row: pd.Series | None,
        exit_row: pd.Series | None,
    ) -> None:
        """Costo spread round-trip: media spread ingresso/uscita (metà spread per lato vs mid)."""
        pair_n = _normalize_pair_symbols(str(sig.get("pair", "")))
        fx_sp = _split_fx_pair(pair_n)
        q_ccy = str(sig.get("quoteCurrency") or (fx_sp[1] if fx_sp else "USD"))
        pip_sz = _pip_size_for_quote(q_ccy)
        lots = float(sig.get("minLotPerTrade") or exit_cfg.get("minLotPerTrade", 0.01))
        if lots < 0.01:
            lots = 0.01
        contract = float(sig.get("fxContractUnitsPerLot") or _FX_UNITS_PER_LOT)
        entry_px = float(sig["entryPrice"])
        if entry_row is None or exit_row is None:
            sig["spread_entry_pips"] = 0.0
            sig["spread_exit_pips"] = 0.0
            sig["spread_round_trip_pips"] = 0.0
            sig["spread_paid_eur"] = 0.0
            sig["spread_note"] = "barre_bid_ask_mancanti"
            return
        se = _bar_spread_pips(entry_row, q_ccy)
        sx = _bar_spread_pips(exit_row, q_ccy)
        rt = (se + sx) / 2.0
        cost_quote = float(rt * pip_sz * lots * contract)
        eur_cost, note = _pnl_quote_to_euro(cost_quote, q_ccy, pair_n, entry_px)
        sig["spread_entry_pips"] = float(se)
        sig["spread_exit_pips"] = float(sx)
        sig["spread_round_trip_pips"] = float(rt)
        sig["spread_paid_eur"] = float(max(0.0, eur_cost))
        sig["spread_note"] = f"RT pips=(ingresso+uscita)/2 su barre 1m Bid+Ask; EUR~{note}"

    def _simulate_single(
        sig_template: dict[str, Any],
        sig_step: tuple[int, int] | None = None,
        prog_local: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        sig = copy.copy(sig_template)
        ts_pd = _to_utc_timestamp(sig.get("timestamp"))
        side = str(sig.get("type", "buy")).lower()
        entry = float(sig["entryPrice"])
        sl = float(sig["stopLoss"])
        tp = float(sig["takeProfit"])
        sl_adj_count = 0
        be_done = False
        be_armed = False
        trail_moved = False

        pair_norm = _normalize_pair_symbols(str(sig.get("pair", "")))
        fx_sp = _split_fx_pair(pair_norm)
        quote_ccy = str(sig.get("quoteCurrency") or (fx_sp[1] if fx_sp else "USD"))
        pip_sz = _pip_size_for_quote(quote_ccy)
        min_lot = float(sig.get("minLotPerTrade") or exit_cfg.get("minLotPerTrade", 0.01))
        if min_lot < 0.01:
            min_lot = 0.01
        sig["minLotPerTrade"] = min_lot

        atr_entry = _signal_entry_atr(sig, exit_cfg)
        atr_e = float(atr_entry) if atr_entry is not None and atr_entry > 0 else 0.0
        tr_ok = bool(tr_active and atr_e > 0)
        be_ok = bool(be_active and atr_e > 0)

        # Soglie in prezzo (× ATR alla voce), come gestione uscite configurabile.
        trigger_be_px = float(be_trigger_mult * atr_e) if be_ok else 0.0
        lock_px = float(be_lock_mult * atr_e) if be_ok else 0.0
        trigger_ts_px = float(tr_act_mult * atr_e) if tr_ok else 0.0
        step_ts_px = float(tr_step_mult * atr_e) if tr_ok else 0.0

        ts_ns = int(ts_pd.value)
        ix_ge = int(np.searchsorted(dt_ns, ts_ns, side="left"))
        ix_gt = int(np.searchsorted(dt_ns, ts_ns, side="right"))
        entry_row_1m = df.iloc[ix_ge] if ix_ge < n_bars else None

        if ix_gt >= n_bars:
            sig["exit_reason"] = "no_exit"
            sig["exit_price"] = entry
            sig["exit_time"] = ts_pd.to_pydatetime()
            sig["realized_pips"] = 0.0
            sig["profit_quote_currency"] = 0.0
            sig["quote_currency"] = quote_ccy
            sig["realized_pnl_eur"] = 0.0
            sig["pnl_conversion_note"] = "no_bars_after_signal"
            sig["spread_entry_pips"] = 0.0
            sig["spread_exit_pips"] = 0.0
            sig["spread_round_trip_pips"] = 0.0
            sig["spread_paid_eur"] = 0.0
            sig["stopLossAdjustmentCount"] = 0
            return sig

        start_ix = ix_gt
        n_path = n_bars - start_ix
        bar_stride = 1
        if n_path > 50_000:
            bar_stride = max(8000, n_path // 30)
        elif n_path > 5000:
            bar_stride = max(2000, n_path // 25)
        elif n_path > 500:
            bar_stride = max(100, n_path // 20)

        closed = False
        peak_price = float(entry)
        trough_price = float(entry)

        for k in range(n_path):
            j = start_ix + k
            pos1 = k + 1
            if prog_local is not None and sig_step is not None and n_path > 0:
                if pos1 == 1 or pos1 == n_path or (pos1 % bar_stride == 0):
                    pct = 100 * pos1 // n_path
                    _simulate_1m_progress_maybe(
                        prog_local,
                        f"Segnale {sig_step[0]}/{sig_step[1]} · barre 1m {pos1}/{n_path} ({pct}%)",
                    )
            high_bid = float(hb[j])
            low_bid = float(lb[j])
            high_ask = float(ha[j])
            low_ask = float(la[j])
            exit_ts = pd.Timestamp(int(dt_ns[j]), unit="ns", tz="UTC")

            if side == "buy":
                peak_price = max(peak_price, high_bid)
                profitto_corrente = high_bid - entry
                profitto_massimo = peak_price - entry

                # 1) Break-even (priorità): SL ancora sotto ingresso e profitto ≥ trigger.
                if be_ok and (not be_done) and profitto_corrente >= trigger_be_px and sl < entry:
                    old_sl = sl
                    new_sl = max(sl, entry + lock_px)
                    if _sl_price_moved(old_sl, new_sl, entry):
                        sl_adj_count += 1
                    sl = new_sl
                    be_done = True
                    be_armed = True
                # 2) Trailing da picco: attivo se il massimo favorevole ha superato il trigger TS.
                if tr_ok and profitto_massimo >= trigger_ts_px:
                    livello_ts = peak_price - trigger_ts_px
                    if livello_ts > sl + step_ts_px:
                        old_sl = sl
                        if _sl_price_moved(old_sl, livello_ts, entry):
                            sl_adj_count += 1
                        sl = livello_ts
                        trail_moved = True

                sl_hit = low_bid <= sl
                tp_hit = high_bid >= tp
                if sl_hit or tp_hit:
                    # Regola conservativa: se entrambi toccati nella stessa barra, assume SL prima.
                    exit_price = sl if sl_hit else tp
                    if sl_hit:
                        sig["exit_reason"] = (
                            "SL_TRAIL" if trail_moved else ("SL_BE" if be_armed else "SL")
                        )
                    else:
                        sig["exit_reason"] = "TP"
                    sig["exit_price"] = float(exit_price)
                    sig["exit_time"] = exit_ts.to_pydatetime()
                    _attach_pnl(sig, entry, float(exit_price))
                    _attach_spread(sig, entry_row_1m, df.iloc[j])
                    closed = True
                    break
            else:
                trough_price = min(trough_price, low_ask)
                profitto_corrente = entry - low_ask
                profitto_massimo = entry - trough_price

                if be_ok and (not be_done) and profitto_corrente >= trigger_be_px and sl > entry:
                    old_sl = sl
                    new_sl = min(sl, entry - lock_px)
                    if _sl_price_moved(old_sl, new_sl, entry):
                        sl_adj_count += 1
                    sl = new_sl
                    be_done = True
                    be_armed = True
                if tr_ok and profitto_massimo >= trigger_ts_px:
                    livello_ts = trough_price + trigger_ts_px
                    if livello_ts < sl - step_ts_px:
                        old_sl = sl
                        if _sl_price_moved(old_sl, livello_ts, entry):
                            sl_adj_count += 1
                        sl = livello_ts
                        trail_moved = True

                sl_hit = high_ask >= sl
                tp_hit = low_ask <= tp
                if sl_hit or tp_hit:
                    exit_price = sl if sl_hit else tp
                    if sl_hit:
                        sig["exit_reason"] = (
                            "SL_TRAIL" if trail_moved else ("SL_BE" if be_armed else "SL")
                        )
                    else:
                        sig["exit_reason"] = "TP"
                    sig["exit_price"] = float(exit_price)
                    sig["exit_time"] = exit_ts.to_pydatetime()
                    _attach_pnl(sig, entry, float(exit_price))
                    _attach_spread(sig, entry_row_1m, df.iloc[j])
                    closed = True
                    break

        if not closed:
            last_idx = n_bars - 1
            exit_mid = float((cb[last_idx] + ca[last_idx]) / 2.0)
            sig["exit_reason"] = "no_exit"
            sig["exit_price"] = exit_mid
            sig["exit_time"] = pd.Timestamp(int(dt_ns[last_idx]), unit="ns", tz="UTC").to_pydatetime()
            _attach_pnl(sig, entry, exit_mid)
            _attach_spread(sig, entry_row_1m, df.iloc[last_idx])
        sig["stopLossAdjustmentCount"] = sl_adj_count
        return sig

    result: list[dict[str, Any]] = []
    open_until: list[pd.Timestamp] = []
    skipped = 0
    for step_no, i in enumerate(ordered_idx, start=1):
        raw = signals[i]
        ts = _to_utc_timestamp(raw.get("timestamp"))
        open_until = [u for u in open_until if u > ts]
        if len(open_until) >= max_sim:
            skipped += 1
            _simulate_1m_progress_maybe(
                prog,
                f"Segnale {step_no}/{total_sig_candidates}: saltato (limite posizioni aperte)",
            )
            continue
        step_tuple = (step_no, total_sig_candidates) if prog is not None else None
        done = _simulate_single(raw, sig_step=step_tuple, prog_local=prog)
        result.append(done)
        open_until.append(_to_utc_timestamp(done.get("exit_time")))
        _simulate_1m_progress_maybe(
            prog,
            f"Segnale {step_no}/{total_sig_candidates} completato "
            f"({100 * step_no // max(1, total_sig_candidates)}% segnali)",
        )

    if prog is not None:
        _simulate_1m_progress_maybe(
            prog,
            f"Simulazione 1m: completata ({len(result)} segnali accettati, {skipped} saltati).",
            force=True,
        )

    logs.append(
        "simulazione 1m: spread calcolato da Bid+Ask (merge inner) su barra ingresso "
        "(prima barra con datetime>=segnale) e barra uscita; RT pips=(spread_in+spread_out)/2."
    )
    if max_sim >= 10**6:
        logs.append(
            f"simulazione uscite 1M completata: {len(result)} segnali "
            f"(maxSimultaneousTrades assente o illimitato)"
        )
    else:
        logs.append(
            f"simulazione uscite 1M: maxSimultaneousTrades={max_sim} → "
            f"accettati {len(result)}/{len(signals)} (saltati {skipped} per limite posizioni aperte)"
        )
    return result, logs


def _run_backtest_parquet_parallel_workers(unique_count: int) -> tuple[bool, int]:
    """
    Ritorna (attiva_parallel, max_workers).
    STRIKEZONE_PARALLEL_PARQUET: vuoto/0/false/no → off; 1/true/yes → on con min(8, unique);
    intero 2–8 → on con quel tetto worker (mai oltre unique_count).
    """
    raw = (os.environ.get("STRIKEZONE_PARALLEL_PARQUET") or "").strip().lower()
    if raw in ("", "0", "false", "no"):
        return False, 1
    if raw in ("1", "true", "yes"):
        return True, max(1, min(8, unique_count))
    if raw.isdigit():
        n = int(raw, 10)
        if n <= 0:
            return False, 1
        return True, max(1, min(n, 8, unique_count))
    return False, 1


def _resolution_frame_from_cache(
    df_by_resolution: dict[str, pd.DataFrame],
    wanted: str,
) -> pd.DataFrame | None:
    """Trova un DataFrame già caricato per `wanted` ignorando maiuscole/minuscole sulla chiave."""
    w = (wanted or "").strip()
    if not w:
        return None
    if w in df_by_resolution:
        df = df_by_resolution[w]
        return df if df is not None and not df.empty else None
    w_low = w.lower()
    for k, df in df_by_resolution.items():
        if (k or "").strip().lower() == w_low:
            return df if df is not None and not df.empty else None
    return None


def _reuse_or_load_one_minute_frame(
    pair: str,
    bucket_name: str,
    start_date: datetime,
    end_date: datetime,
    df_by_resolution: dict[str, pd.DataFrame],
    logs: list[str],
) -> pd.DataFrame:
    """Riusa 1m/1M già in cache da uno slot timeframe, altrimenti scarica da GCS."""
    for cand in ("1M", "1m", "1MIN", "1min"):
        hit = _resolution_frame_from_cache(df_by_resolution, cand)
        if hit is not None:
            logs.append(f"simulazione 1m: riuso dati già caricati (risoluzione {cand!r})")
            return hit
    probe: list[str] = []
    df = _load_timeframe_parquet(
        pair.strip(),
        "1M",
        bucket_name,
        start_date,
        end_date,
        debug_logs=probe,
    )
    logs.extend(probe)
    return df


def _run_backtest_load_resolution_frames(
    pair_clean: str,
    slots: list[tuple[str, str]],
    bucket_name: str,
    start_dt: datetime,
    end_dt: datetime,
    logs: list[str],
) -> dict[str, pd.DataFrame]:
    """Carica un DataFrame per ogni risoluzione distinta richiesta dagli slot (dedup per stringa)."""
    unique: list[str] = []
    for _, res in slots:
        rs = (res or "").strip()
        if rs and rs not in unique:
            unique.append(rs)

    def _load_one(resolution: str) -> tuple[str, pd.DataFrame, list[str]]:
        probe: list[str] = []
        df = _load_timeframe_parquet(
            pair_clean,
            resolution,
            bucket_name,
            start_dt,
            end_dt,
            debug_logs=probe,
        )
        return resolution, df, probe

    out: dict[str, pd.DataFrame] = {}
    use_parallel, workers = _run_backtest_parquet_parallel_workers(len(unique))
    if use_parallel and len(unique) > 1:
        logs.append(
            f"caricamento Parquet parallelo ({len(unique)} risoluzioni, workers={workers}, "
            f"STRIKEZONE_PARALLEL_PARQUET={os.environ.get('STRIKEZONE_PARALLEL_PARQUET', '')!r})"
        )
        with ThreadPoolExecutor(max_workers=workers) as pool:
            future_map = {pool.submit(_load_one, res): res for res in unique}
            for fut in as_completed(future_map):
                res, df, probe = fut.result()
                out[res] = df
                logs.extend(probe)
    else:
        for res in unique:
            res_key, df, probe = _load_one(res)
            out[res_key] = df
            logs.extend(probe)
    return out


def _load_timeframe_parquet(
    pair: str,
    resolution: str,
    bucket_name: str,
    start_date: datetime,
    end_date: datetime,
    debug_logs: list[str] | None = None,
) -> pd.DataFrame:
    """
    Carica i Parquet mensili Bid/Ask da GCS (path come main_old).
    Ogni chiamata è sequenziale sui mesi; run_backtest può lanciare più risoluzioni in parallelo
    (vedi STRIKEZONE_PARALLEL_PARQUET). Su emulatore macOS i thread + fork restano delicati: opt-in.
    """
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    pair_upper = pair.strip().upper()
    res_raw = resolution.strip()
    # Alcuni bucket salvano timeframe in minuscolo (15m/4h/1d), altri in maiuscolo.
    # Proviamo entrambe le varianti per evitare falsi "0 righe".
    res_candidates: list[str] = []
    for candidate in (res_raw, res_raw.upper(), res_raw.lower()):
        if candidate and candidate not in res_candidates:
            res_candidates.append(candidate)
    chunks: list[pd.DataFrame] = []
    for year, month_str in _iter_year_months(start_date, end_date):
        loaded_for_month = False
        for res_path in res_candidates:
            base_path = f"historical_data/{pair_upper}/{res_path}/{year}/{month_str}"
            try:
                bid_path = f"{base_path}_Bid.parquet"
                ask_path = f"{base_path}_Ask.parquet"
                probe_line = (
                    f"probe bucket={bucket_name} base={base_path} "
                    f"bid={bid_path} ask={ask_path}"
                )
                _logger.info("run_backtest parquet %s", probe_line)
                if debug_logs is not None:
                    debug_logs.append(probe_line)

                b_blob = bucket.blob(bid_path)
                a_blob = bucket.blob(ask_path)
                bid_exists = b_blob.exists()
                ask_exists = a_blob.exists()
                exists_line = (
                    f"exists base={base_path} bid_exists={bid_exists} ask_exists={ask_exists}"
                )
                _logger.info("run_backtest parquet %s", exists_line)
                if debug_logs is not None:
                    debug_logs.append(exists_line)

                if not bid_exists or not ask_exists:
                    continue

                df_bid = pd.read_parquet(io.BytesIO(b_blob.download_as_bytes()))
                df_ask = pd.read_parquet(io.BytesIO(a_blob.download_as_bytes()))
                _logger.info(
                    "run_backtest parquet schema base=%s bid_cols=%s ask_cols=%s",
                    base_path,
                    list(df_bid.columns),
                    list(df_ask.columns),
                )
                if debug_logs is not None:
                    debug_logs.append(
                        f"schema base={base_path} bid_cols={list(df_bid.columns)} ask_cols={list(df_ask.columns)}"
                    )

                df_bid = _normalize_side_ohlc(df_bid, "bid")
                df_ask = _normalize_side_ohlc(df_ask, "ask")
                chunks.append(pd.merge(df_bid, df_ask, on="datetime", how="inner"))
                loaded_for_month = True
                break
            except Exception as e:
                _logger.warning("run_backtest parquet skip %s: %s", base_path, e)
                if debug_logs is not None:
                    debug_logs.append(f"skip base={base_path} error={e}")
                continue
        if not loaded_for_month and debug_logs is not None:
            debug_logs.append(
                f"missing month={year}-{month_str} resolutions={','.join(res_candidates)}"
            )
    if not chunks:
        return pd.DataFrame()
    df = pd.concat(chunks, ignore_index=True)
    df["datetime"] = pd.to_datetime(df["datetime"], utc=True)
    ts_start = pd.Timestamp(start_date)
    ts_end = pd.Timestamp(end_date)
    if ts_start.tzinfo is None:
        ts_start = ts_start.tz_localize("UTC")
    if ts_end.tzinfo is None:
        ts_end = ts_end.tz_localize("UTC")
    df = df[(df["datetime"] >= ts_start) & (df["datetime"] <= ts_end)]
    return df.sort_values("datetime").reset_index(drop=True)


def _strategy_timeframe_slots(strategy_doc: dict[str, Any]) -> list[tuple[str, str]]:
    """Ruoli operativo | medio | lungo | test con risoluzione OHLC (es. 15m, 4h)."""
    tf = strategy_doc.get("timeframes")
    if not isinstance(tf, dict):
        return []
    out: list[tuple[str, str]] = []
    for role in ("operativo", "medio", "lungo", "test"):
        raw = tf.get(role)
        if isinstance(raw, str) and raw.strip():
            out.append((role, raw.strip()))
    return out


def _auth_error_response(message: str, status: int, headers: dict) -> https_fn.Response:
    return https_fn.Response(
        json.dumps({"error": message, "message": message}),
        status=status,
        headers=headers,
    )


@https_fn.on_request()
def get_capital_credentials(req: https_fn.Request) -> https_fn.Response:
    """POST: JSON { apiKey, login, password } decrittati (come setting_view_model)."""
    headers = cors_headers(req)
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=headers)

    try:
        uid = verify_token(req)
    except ValueError as e:
        return _auth_error_response(str(e), 401, headers)
    except Exception as e:
        return _auth_error_response(str(e), 401, headers)

    if req.method != "POST":
        return https_fn.Response(
            json.dumps({"error": "Usa POST", "message": "Usa POST"}),
            status=405,
            headers=headers,
        )

    snap = get_db().collection("capital_credentials").document(uid).get()
    if not snap.exists:
        return https_fn.Response("{}", status=200, headers=headers)

    creds = snap.to_dict() or {}
    try:
        out = {
            "apiKey": _decrypt_field(str(creds.get("apiKey", ""))),
            "login": _decrypt_field(str(creds.get("login", ""))),
            "password": _decrypt_field(str(creds.get("password", ""))),
        }
    except (InvalidToken, ValueError, TypeError) as e:
        _logger.exception("Decrypt capital_credentials failed for uid=%s", uid)
        return https_fn.Response(
            json.dumps(
                {
                    "message": "Impossibile decrittare le credenziali salvate. "
                    "Verifica CAPITAL_CREDENTIALS_FERNET_KEY / ENCRYPTION_KEY.",
                    "error": str(e),
                }
            ),
            status=500,
            headers=headers,
        )
    except Exception as e:
        _logger.exception("capital_credentials read error uid=%s", uid)
        return https_fn.Response(
            json.dumps({"message": str(e), "error": str(e)}),
            status=500,
            headers=headers,
        )

    return https_fn.Response(
        json.dumps(out, ensure_ascii=False),
        status=200,
        headers=headers,
    )


@https_fn.on_request()
def save_capital_credentials(req: https_fn.Request) -> https_fn.Response:
    """POST body: apiKey, login, password (Flutter setting_view_model)."""
    headers = cors_headers(req)
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=headers)

    try:
        uid = verify_token(req)
    except ValueError as e:
        return _auth_error_response(str(e), 401, headers)
    except Exception as e:
        return _auth_error_response(str(e), 401, headers)

    if req.method != "POST":
        return https_fn.Response(
            json.dumps({"message": "Usa POST", "error": "Usa POST"}),
            status=405,
            headers=headers,
        )

    body = parse_request_json(req)
    if not body or not all(k in body for k in ("apiKey", "login", "password")):
        return https_fn.Response(
            json.dumps(
                {
                    "message": "Campi obbligatori: apiKey, login, password",
                    "error": "missing_fields",
                }
            ),
            status=400,
            headers=headers,
        )

    try:
        encrypted = {
            "apiKey": _encrypt_field(str(body["apiKey"])),
            "login": _encrypt_field(str(body["login"])),
            "password": _encrypt_field(str(body["password"])),
            "userId": uid,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
    except Exception as e:
        _logger.exception("encrypt capital_credentials uid=%s", uid)
        return https_fn.Response(
            json.dumps(
                {
                    "message": "Configurazione chiave di cifratura non disponibile. "
                    "In emulatore imposta CAPITAL_CREDENTIALS_FERNET_KEY (chiave Fernet).",
                    "error": str(e),
                }
            ),
            status=500,
            headers=headers,
        )

    get_db().collection("capital_credentials").document(uid).set(encrypted)
    return https_fn.Response(
        json.dumps({"ok": True, "userId": uid}),
        status=200,
        headers=headers,
    )


@https_fn.on_request()
def delete_capital_credentials(req: https_fn.Request) -> https_fn.Response:
    headers = cors_headers(req)
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=headers)

    try:
        uid = verify_token(req)
    except ValueError as e:
        return _auth_error_response(str(e), 401, headers)
    except Exception as e:
        return _auth_error_response(str(e), 401, headers)

    if req.method != "POST":
        return https_fn.Response(
            json.dumps({"message": "Usa POST", "error": "Usa POST"}),
            status=405,
            headers=headers,
        )

    get_db().collection("capital_credentials").document(uid).delete()
    return https_fn.Response(
        json.dumps({"ok": True}),
        status=200,
        headers=headers,
    )


def _capital_com_proxy_execute(
    uid: str,
    api_key: str,
    login: str,
    password: str,
    endpoint: str,
    method: str,
    body: dict[str, Any],
) -> tuple[int, dict[str, Any]]:
    """
    Esegue la richiesta verso Capital.com (stesso uid, sessione in cache).
    Ritorna (status HTTP della Cloud Function, dict da serializzare in JSON).
    In caso di successo verso Capital: status 200 e body {"status": <codice API>, "data": ...}.
    """
    with _CAPITAL_PROXY_GLOBAL_LOCK:
        if _capital_com_debug_log_secrets():
            _logger.warning(
                "CAPITAL_COM_DEBUG_LOG_SECRETS: POST %s/api/v1/session | "
                "X-CAP-API-KEY=%r | body=%s",
                CAPITAL_API_BASE,
                api_key,
                json.dumps(
                    {
                        "identifier": login,
                        "password": password,
                        "encryptedPassword": False,
                    },
                    ensure_ascii=False,
                ),
            )

        def login_capital() -> tuple[str | None, str | None]:
            r = _CAPITAL_HTTP_SESSION.post(
                f"{CAPITAL_API_BASE}/api/v1/session",
                headers={"X-CAP-API-KEY": api_key, "Content-Type": "application/json"},
                json={
                    "identifier": login,
                    "password": password,
                    "encryptedPassword": False,
                },
                timeout=30,
            )
            if r.status_code != 200:
                raise ValueError(r.text)
            return r.headers.get("CST"), r.headers.get("X-SECURITY-TOKEN")

        cached = SESSION_CACHE.get(uid)
        if cached:
            cst, security_token, _ts = cached
        else:
            try:
                cst, security_token = login_capital()
                SESSION_CACHE[uid] = (cst, security_token, time.time())
            except Exception as e:
                return (
                    401,
                    {"message": f"Auth failed: {e}", "error": "capital_auth"},
                )

        url = f"{CAPITAL_API_BASE}{endpoint}"
        req_headers = {
            "X-CAP-API-KEY": api_key,
            "CST": cst or "",
            "X-SECURITY-TOKEN": security_token or "",
            "Content-Type": "application/json",
        }

        if _capital_com_debug_log_secrets():
            _logger.warning(
                "CAPITAL_COM_DEBUG_LOG_SECRETS: %s %s | X-CAP-API-KEY=%r | CST=%r | "
                "X-SECURITY-TOKEN=%r | body=%s",
                method,
                url,
                api_key,
                cst,
                security_token,
                json.dumps(body, ensure_ascii=False) if body else "{}",
            )

        def do_request() -> requests.Response:
            if method == "GET":
                return _CAPITAL_HTTP_SESSION.get(url, headers=req_headers, timeout=60)
            if method == "POST":
                return _CAPITAL_HTTP_SESSION.post(url, headers=req_headers, json=body, timeout=60)
            if method == "PUT":
                return _CAPITAL_HTTP_SESSION.put(url, headers=req_headers, json=body, timeout=60)
            if method == "DELETE":
                return _CAPITAL_HTTP_SESSION.delete(url, headers=req_headers, timeout=60)
            raise ValueError(f"Method non supportata: {method}")

        try:
            resp = do_request()
            if resp.status_code == 401:
                try:
                    cst, security_token = login_capital()
                    SESSION_CACHE[uid] = (cst, security_token, time.time())
                    req_headers["CST"] = cst or ""
                    req_headers["X-SECURITY-TOKEN"] = security_token or ""
                    resp = do_request()
                except Exception as e:
                    return (
                        401,
                        {"message": f"Renew failed: {e}", "error": "renew"},
                    )
            try:
                response_data = resp.json()
            except Exception:
                response_data = {"error": resp.text}
            return (200, {"status": resp.status_code, "data": response_data})
        except requests.exceptions.RequestException as e:
            _logger.exception("capital_com_proxy HTTP uid=%s", uid)
            return (
                502,
                {
                    "message": f"Errore di rete verso Capital.com: {e}",
                    "error": "upstream_network",
                },
            )
        except ValueError as e:
            return (400, {"message": str(e), "error": "bad_request"})
        except Exception as e:
            _logger.exception("capital_com_proxy uid=%s", uid)
            return (500, {"message": f"Proxy error: {e}", "error": "proxy"})


def _capital_com_proxy_body(
    req: https_fn.Request, headers: dict[str, str]
) -> https_fn.Response:
    try:
        uid = verify_token(req)
    except ValueError as e:
        return _auth_error_response(str(e), 401, headers)
    except Exception as e:
        return _auth_error_response(str(e), 401, headers)

    if req.method != "POST":
        return https_fn.Response(
            json.dumps({"message": "Usa POST", "error": "Usa POST"}),
            status=405,
            headers=headers,
        )

    snap = get_db().collection("capital_credentials").document(uid).get()
    if not snap.exists:
        return https_fn.Response(
            json.dumps({"message": "No credentials", "error": "no_credentials"}),
            status=400,
            headers=headers,
        )
    creds = snap.to_dict() or {}
    try:
        api_key = _decrypt_field(str(creds.get("apiKey", "")))
        login = _decrypt_field(str(creds.get("login", "")))
        password = _decrypt_field(str(creds.get("password", "")))
    except (InvalidToken, ValueError, TypeError) as e:
        return https_fn.Response(
            json.dumps({"message": f"Decrypt error: {e}", "error": "decrypt"}),
            status=500,
            headers=headers,
        )

    payload = parse_request_json(req)
    endpoint = payload.get("endpoint")
    method = str(payload.get("method") or "GET").upper()
    body = payload.get("body") or {}
    if not isinstance(body, dict):
        body = {}
    if not endpoint or not isinstance(endpoint, str):
        return https_fn.Response(
            json.dumps({"message": "Campo endpoint obbligatorio", "error": "invalid_body"}),
            status=400,
            headers=headers,
        )

    out_status, out_body = _capital_com_proxy_execute(
        uid, api_key, login, password, endpoint, method, body
    )
    return https_fn.Response(
        json.dumps(out_body),
        status=out_status,
        headers=headers,
    )


@https_fn.on_request(
    cors=CorsOptions(
        cors_origins="*",
        cors_methods=["get", "post", "options", "put", "delete"],
    ),
    invoker="public",
)
def capital_com_proxy(req: https_fn.Request) -> https_fn.Response:
    """
    POST JSON: endpoint (path Capital API), method (GET/POST/PUT/DELETE), body opzionale.
    Usa credenziali da capital_credentials/{uid}. Risposta come main_old: HTTP 200 con
    {"status": <codice Capital>, "data": ...} per compatibilità con market_data_provider.

    CORS: Flask-Cors via CorsOptions (come da doc Firebase); invoker public per Gen2 da browser.
    Le risposte JSON usano solo Content-Type; gli header CORS li aggiunge il wrapper.
    """
    headers = {"Content-Type": "application/json"}
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers={})

    try:
        return _capital_com_proxy_body(req, headers)
    except Exception as e:
        _logger.exception("capital_com_proxy fatal")
        return https_fn.Response(
            json.dumps({"message": str(e), "error": "internal"}),
            status=500,
            headers=headers,
        )


@https_fn.on_call(cors=CorsOptions(cors_origins="*"))
def capital_com_proxy_call(req: https_fn.CallableRequest) -> dict[str, Any]:
    """
    Stesso contratto di capital_com_proxy (HTTP 200 + {"status", "data"} in caso di successo),
    esposto come callable per Flutter web / emulatore (evita fetch diretto e problemi CORS).
    """
    try:
        return _capital_com_proxy_call_impl(req)
    except https_fn.HttpsError:
        raise
    except Exception:
        _logger.exception("capital_com_proxy_call: errore non gestito")
        raise


def _capital_com_proxy_call_impl(req: https_fn.CallableRequest) -> dict[str, Any]:
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Autenticazione richiesta.",
        )
    uid = req.auth.uid
    payload = _callable_data(req)
    endpoint = payload.get("endpoint")
    method = str(payload.get("method") or "GET").upper()
    raw_body = payload.get("body") or {}
    body: dict[str, Any] = raw_body if isinstance(raw_body, dict) else {}
    if not endpoint or not isinstance(endpoint, str):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Campo endpoint obbligatorio",
        )

    snap = get_db().collection("capital_credentials").document(uid).get()
    if not snap.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            message="No credentials",
        )
    creds = snap.to_dict() or {}
    try:
        api_key = _decrypt_field(str(creds.get("apiKey", "")))
        login = _decrypt_field(str(creds.get("login", "")))
        password = _decrypt_field(str(creds.get("password", "")))
    except (InvalidToken, ValueError, TypeError) as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Decrypt error: {e}",
        )

    out_status, out_body = _capital_com_proxy_execute(
        uid, api_key, login, password, endpoint, method, body
    )
    if out_status != 200:
        msg = str(out_body.get("message", "Errore proxy"))
        if out_status == 401:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
                message=msg,
            )
        if out_status == 400:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message=msg,
            )
        if out_status == 502:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.UNAVAILABLE,
                message=msg,
            )
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=msg,
        )
    return out_body


@https_fn.on_call(
    # Default Cloud Functions ~60s: con molti mesi di 1m + simulazione uscite si supera facilmente.
    timeout_sec=540,
    memory=1024,
)
def run_backtest(req: https_fn.CallableRequest) -> dict[str, Any]:
    """
    Callable usata da Flutter (httpsCallable('run_backtest')).
    Legge strategy_configs/{uid}, carica i Parquet GCS per ogni timeframe configurato
    (operativo/medio/lungo/test) e restituisce loads[{timeframe, resolution, rows}] + logs.
    """
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Autenticazione richiesta.",
        )

    uid = req.auth.uid
    payload = _callable_data(req)
    pair = payload.get("pair")
    start_date = payload.get("startDate")
    end_date = payload.get("endDate")

    if not pair or not isinstance(pair, str) or not pair.strip():
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="pair obbligatorio",
        )
    try:
        start_dt = _parse_iso_datetime(start_date)
        end_dt = _parse_iso_datetime(end_date)
    except (TypeError, ValueError) as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message=f"startDate/endDate non validi: {e}",
        )
    if start_dt > end_dt:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="startDate deve essere precedente a endDate",
        )

    pair_u = pair.strip().upper()
    _write_backtest_progress(uid, pair_u, "start", "Preparazione backtest…")

    # In emulatore macOS, la lettura Firestore via gRPC nel worker forkato può ancora
    # essere instabile. Se il client passa già i timeframe, usiamo quelli ed evitiamo
    # il read Firestore in questo path.
    payload_timeframes = payload.get("timeframes")
    payload_indicators = payload.get("indicators")
    payload_filters = payload.get("filters")
    payload_exit_rules = payload.get("exitRules")
    raw_doc: dict[str, Any] = {}
    if isinstance(payload_timeframes, dict) and payload_timeframes:
        raw_doc = {"timeframes": payload_timeframes}
        if isinstance(payload_indicators, dict):
            raw_doc["indicators"] = payload_indicators
        if isinstance(payload_filters, dict):
            raw_doc["filters"] = payload_filters
        if isinstance(payload_exit_rules, dict):
            raw_doc["exitRules"] = payload_exit_rules
    else:
        snap = get_db().collection("strategy_configs").document(uid).get()
        raw_doc = snap.to_dict() if snap.exists else {}
    strategy = _serialize_strategy_doc(raw_doc) if raw_doc else {}

    snapshot = {
        "uid": uid,
        "request": {"pair": pair, "startDate": start_date, "endDate": end_date},
        "strategyConfig": strategy,
    }
    _logger.info(
        "run_backtest strategy snapshot\n%s",
        json.dumps(snapshot, indent=2, ensure_ascii=False, default=str),
    )

    logs: list[str] = [
        "--- run_backtest: caricamento Parquet per timeframe ---",
        f"uid: {uid}",
        f"intervallo: pair={pair.strip().upper()!r} start={start_date!r} end={end_date!r}",
        f"bucket: {_BACKTEST_GCS_BUCKET}",
    ]
    loads: list[dict[str, Any]] = []

    if not raw_doc:
        _logger.info("run_backtest early-exit: strategy_configs assente (uid=%s)", uid)
        logs.append("Nessun documento strategy_configs; caricamento saltato.")
        _write_backtest_progress(
            uid,
            pair_u,
            "aborted",
            "Nessuna configurazione timeframe (payload vuoto e strategy_configs assente).",
        )
        return {"loads": loads, "logs": logs, "timing": {}}

    slots = _strategy_timeframe_slots(raw_doc)
    if not slots:
        _logger.info("run_backtest early-exit: nessun timeframe valido in config (uid=%s)", uid)
        logs.append("Nessun timeframe in strategy_configs.timeframes.")
        _write_backtest_progress(
            uid,
            pair_u,
            "aborted",
            "Nessun timeframe valido in strategy_configs.timeframes.",
        )
        return {"loads": loads, "logs": logs, "timing": {}}

    def _wall_ms(t_start: float, t_end: float) -> float:
        return round((t_end - t_start) * 1000.0, 2)

    logs.append(
        "Timeframe richiesti: "
        + ", ".join(f"{role}={res}" for role, res in slots),
    )

    _write_backtest_progress(
        uid,
        pair_u,
        "parquet",
        "Caricamento Parquet da GCS (tutti i timeframe richiesti)…",
    )
    t_wall0 = time.perf_counter()
    df_by_resolution = _run_backtest_load_resolution_frames(
        pair.strip(),
        slots,
        _BACKTEST_GCS_BUCKET,
        start_dt,
        end_dt,
        logs,
    )
    t_after_parquet = time.perf_counter()
    for role, resolution in slots:
        res = (resolution or "").strip()
        n_rows = len(df_by_resolution.get(res, pd.DataFrame()))
        loads.append(
            {
                "timeframe": role,
                "resolution": resolution,
                "rows": n_rows,
            }
        )
        line = f"{role} ({resolution}): {n_rows} righe caricate"
        logs.append(line)
        _logger.info("run_backtest %s", line)
    t_after_loads_meta = time.perf_counter()

    _write_backtest_progress(
        uid,
        pair_u,
        "indicators",
        "Calcolo indicatori, filtri e piano uscite (ATR operativo)…",
    )
    # Associazione indicatori/filtri al timeframe configurato (operativo/medio/lungo)
    # e costruzione di un primo piano "exit rules" basato su ATR del timeframe operativo.
    t_prep0 = time.perf_counter()
    strategy_eval = _strategy_with_defaults(raw_doc)
    df_by_role = {role: df_by_resolution.get(res, pd.DataFrame()) for role, res in slots}
    indicator_snapshot, eval_logs = _compute_indicator_snapshot(df_by_role, strategy_eval)
    logs.extend(eval_logs)

    exit_cfg = strategy_eval.get("exitRules", {})
    op_df = df_by_role.get("operativo", pd.DataFrame())
    atr_value = None
    if op_df is not None and not op_df.empty:
        atr_value = float(_calculate_atr(op_df, 14).iloc[-1])
    sl_atr = float(exit_cfg.get("slAtrMult", 2.0))
    tp_atr = float(exit_cfg.get("tpAtrMult", 4.0))
    exit_plan = {
        "activationScore": exit_cfg.get("activationScore"),
        "maxSimultaneousTrades": exit_cfg.get("maxSimultaneousTrades"),
        "minLotPerTrade": exit_cfg.get("minLotPerTrade", 0.01),
        "slAtrMult": sl_atr,
        "tpAtrMult": tp_atr,
        "breakEven": exit_cfg.get("breakEven", {}),
        "trailingStop": exit_cfg.get("trailingStop", {}),
        "operativoAtr": atr_value,
        "operativoSlDistance": (atr_value * sl_atr) if atr_value is not None else None,
        "operativoTpDistance": (atr_value * tp_atr) if atr_value is not None else None,
    }
    logs.append("indicatori/filtri calcolati con associazione timeframe completata")
    t_prep1 = time.perf_counter()

    _write_backtest_progress(
        uid,
        pair_u,
        "signals",
        "Allineamento barre multi-timeframe e generazione segnali…",
    )
    aligned = _align_role_frames(
        df_by_role,
        strategy_eval,
        _normalize_pair_symbols(pair.strip()),
    )
    generated_signals, gen_logs = _generate_test_signals(
        uid, pair.strip(), aligned, strategy_eval, is_test=True
    )
    logs.extend(gen_logs)
    t_after_generate = time.perf_counter()

    _write_backtest_progress(
        uid,
        pair_u,
        "minute_bars",
        "Caricamento (o riuso) storico 1 minuto per simulazione uscite…",
    )
    # Simulazione chiusura segnali su timeframe 1M (richiesta esplicita).
    # Si usa solo storico successivo al timestamp del segnale.
    df_1m = _reuse_or_load_one_minute_frame(
        pair.strip(),
        _BACKTEST_GCS_BUCKET,
        start_dt,
        end_dt,
        df_by_resolution,
        logs,
    )
    t_after_1m_frame = time.perf_counter()
    simulated_signals, sim_logs = _simulate_signal_closures_1m(
        generated_signals,
        df_1m,
        strategy_eval.get("exitRules", {}),
        progress_uid=uid,
        progress_pair_upper=pair_u,
    )
    logs.extend(sim_logs)
    t_after_simulate = time.perf_counter()

    _write_backtest_progress(
        uid,
        pair_u,
        "save",
        "Salvataggio segnali di test su Firestore…",
    )
    saved_count = _replace_test_signals(uid, pair.strip(), start_dt, end_dt, simulated_signals)
    logs.append(f"test_signals salvati: {saved_count}")
    t_after_save = time.perf_counter()

    timing_ms: dict[str, Any] = {
        "parquetLoadMs": _wall_ms(t_wall0, t_after_parquet),
        "loadsSummaryMs": _wall_ms(t_after_parquet, t_after_loads_meta),
        "indicatorSnapshotAndExitPlanMs": _wall_ms(t_prep0, t_prep1),
        "alignAndGenerateSignalsMs": _wall_ms(t_prep1, t_after_generate),
        "oneMinuteFrameMs": _wall_ms(t_after_generate, t_after_1m_frame),
        "simulate1mMs": _wall_ms(t_after_1m_frame, t_after_simulate),
        "replaceTestSignalsMs": _wall_ms(t_after_simulate, t_after_save),
        "totalWallMs": _wall_ms(t_wall0, t_after_save),
    }

    min_lot_rpt = float(exit_cfg.get("minLotPerTrade", 0.01))
    if min_lot_rpt < 0.01:
        min_lot_rpt = 0.01
    total_pips = sum(float(s.get("realized_pips") or 0) for s in simulated_signals)
    total_eur = sum(float(s.get("realized_pnl_eur") or 0) for s in simulated_signals)
    total_spread_pips = sum(float(s.get("spread_round_trip_pips") or 0) for s in simulated_signals)
    total_spread_eur = sum(float(s.get("spread_paid_eur") or 0) for s in simulated_signals)
    performance_report = {
        "accountCurrency": "EUR",
        "minLotPerTrade": min_lot_rpt,
        "fxContractUnitsPerLot": _FX_UNITS_PER_LOT,
        "signalCount": len(simulated_signals),
        "totalRealizedPips": total_pips,
        "totalRealizedPnlEuro": total_eur,
        "totalSpreadRoundTripPips": total_spread_pips,
        "totalSpreadPaidEuro": total_spread_eur,
        "spreadNote": (
            "Spread: parquet Bid+Ask uniti per ogni timeframe; su 1m costo RT stimato come "
            "media spread (pips) barra ingresso e uscita, valorizzato al lotto minimo (EUR)."
        ),
        "pnlNote": (
            "P&L EUR: USD→EUR con EURUSD ingresso su EURUSD; "
            "JPY→EUR con EURJPY ingresso su EURJPY; altrimenti tassi fallback "
            f"(EURUSD={_EUR_USD_FALLBACK}, EURJPY={_EUR_JPY_FALLBACK})."
        ),
    }
    logs.append(
        f"report: {len(simulated_signals)} segnali, Σ pips={total_pips:.2f}, Σ P&L EUR={total_eur:.2f}, "
        f"Σ spread RT pips={total_spread_pips:.2f}, Σ spread EUR={total_spread_eur:.2f}"
    )

    _write_backtest_progress(
        uid,
        pair_u,
        "done",
        f"Completato: {saved_count} segnali salvati.",
    )

    return {
        "loads": loads,
        "logs": logs,
        "indicatorSnapshot": indicator_snapshot,
        "filterConfig": strategy_eval.get("filters", {}),
        "exitPlan": exit_plan,
        "generatedSignals": saved_count,
        "performanceReport": performance_report,
        "timing": timing_ms,
    }


def _app_tf_token_to_capital_resolution(token: str) -> str | None:
    """Token UI strategy_configs.timeframes (es. 15m) → query Capital `resolution`."""
    t = (token or "").strip().lower()
    m: dict[str, str] = {
        "1m": "MINUTE",
        "tick": "MINUTE",
        "3m": "MINUTE_3",
        "5m": "MINUTE_5",
        "10m": "MINUTE_10",
        "15m": "MINUTE_15",
        "30m": "MINUTE_30",
        "45m": "MINUTE_45",
        "1h": "HOUR",
        "60m": "HOUR",
        "2h": "HOUR_2",
        "3h": "HOUR_3",
        "4h": "HOUR_4",
        "1d": "DAY",
        "1w": "WEEK",
        "w": "WEEK",
    }
    return m.get(t)


def _parse_capital_prices_to_merged_df(data: dict[str, Any], logs: list[str]) -> pd.DataFrame:
    """Converte il body Capital `prices` in un DataFrame merge bid/ask (stesso schema Parquet)."""
    prices = data.get("prices")
    if not isinstance(prices, list) or not prices:
        logs.append("Capital prices: nessuna lista `prices`")
        return pd.DataFrame()
    rows_b: list[dict[str, Any]] = []
    rows_a: list[dict[str, Any]] = []
    for p in prices:
        if not isinstance(p, dict):
            continue
        ts_raw = p.get("snapshotTimeUTC") or p.get("snapshotTime")
        if not ts_raw:
            continue
        ts = pd.to_datetime(ts_raw, utc=True)
        op = p.get("openPrice") if isinstance(p.get("openPrice"), dict) else {}
        hi = p.get("highPrice") if isinstance(p.get("highPrice"), dict) else {}
        lo = p.get("lowPrice") if isinstance(p.get("lowPrice"), dict) else {}
        cl = p.get("closePrice") if isinstance(p.get("closePrice"), dict) else {}
        rows_b.append(
            {
                "datetime": ts,
                "open_bid": op.get("bid"),
                "high_bid": hi.get("bid"),
                "low_bid": lo.get("bid"),
                "close_bid": cl.get("bid"),
            }
        )
        rows_a.append(
            {
                "datetime": ts,
                "open_ask": op.get("ask"),
                "high_ask": hi.get("ask"),
                "low_ask": lo.get("ask"),
                "close_ask": cl.get("ask"),
            }
        )
    if not rows_b:
        return pd.DataFrame()
    df_b = pd.DataFrame(rows_b)
    df_a = pd.DataFrame(rows_a)
    df = pd.merge(df_b, df_a, on="datetime", how="inner")
    df = df.dropna(subset=["open_bid", "close_bid", "open_ask", "close_ask"])
    return df.sort_values("datetime").reset_index(drop=True)


def _fetch_capital_prices_merged(
    uid: str,
    api_key: str,
    login: str,
    password: str,
    epic: str,
    capital_resolution: str,
    max_points: int,
    logs: list[str],
) -> pd.DataFrame:
    q_epic = epic.strip().upper()
    endpoint = f"/api/v1/prices/{q_epic}?resolution={capital_resolution}&max={max_points}"
    st, body = _capital_com_proxy_execute(uid, api_key, login, password, endpoint, "GET", {})
    if st != 200:
        logs.append(f"Capital proxy HTTP {st}: {str(body)[:240]}")
        return pd.DataFrame()
    inner_status = body.get("status")
    if inner_status is not None and int(inner_status) != 200:
        logs.append(f"Capital API status={inner_status}: {str(body)[:400]}")
        return pd.DataFrame()
    payload = body.get("data")
    if not isinstance(payload, dict):
        logs.append(f"Capital `data` non dict: {type(payload)}")
        return pd.DataFrame()
    return _parse_capital_prices_to_merged_df(payload, logs)


def _live_capital_df_by_role(
    uid: str,
    api_key: str,
    login: str,
    password: str,
    epic: str,
    slots: list[tuple[str, str]],
    max_points: int,
    logs: list[str],
) -> dict[str, pd.DataFrame]:
    out: dict[str, pd.DataFrame] = {}
    for role, token in slots:
        cap_res = _app_tf_token_to_capital_resolution(token)
        if not cap_res:
            logs.append(f"live Capital: timeframe {token!r} (ruolo {role}) non mappato")
            return {}
        df = _fetch_capital_prices_merged(
            uid, api_key, login, password, epic, cap_res, max_points, logs
        )
        if df.empty:
            logs.append(f"live Capital: dati vuoti epic={epic} role={role} res={cap_res}")
            return {}
        out[role] = df
        logs.append(f"live Capital: {epic} {role}={token!r}→{cap_res} righe={len(df)}")
    return out


def _ts_equal_bar(a: Any, b: Any) -> bool:
    try:
        ta = pd.Timestamp(a)
        tb = pd.Timestamp(b)
        if ta.tzinfo is None:
            ta = ta.tz_localize("UTC")
        if tb.tzinfo is None:
            tb = tb.tz_localize("UTC")
        return bool(ta == tb)
    except Exception:
        return False


def _filter_signals_to_last_execution_bar(
    signals: list[dict[str, Any]], aligned: pd.DataFrame
) -> list[dict[str, Any]]:
    """Solo segnali la cui barra di esecuzione coincide con l’ultima riga allineata (evita storico)."""
    if not signals or aligned is None or len(aligned) < 2:
        return []
    last_ts = aligned.iloc[-1]["datetime"]
    return [s for s in signals if _ts_equal_bar(s.get("timestamp"), last_ts)]


def _persist_live_signal_doc(uid: str, sig: dict[str, Any], logs: list[str]) -> str | None:
    """Salva un segnale live con lo stesso limite maxSimultaneousTrades di save_live_signal."""
    pair_norm = _normalize_pair_symbols(str(sig.get("pair") or ""))
    if not pair_norm:
        return None
    snap_cfg = get_db().collection("strategy_configs").document(uid).get()
    exit_rules = (snap_cfg.to_dict() or {}).get("exitRules") or {}
    max_sim = _exit_rules_max_simultaneous(exit_rules)
    if max_sim < 10**6:
        open_n = _count_open_live_signals(uid, pair_norm, limit_scan=500)
        if open_n >= max_sim:
            logs.append(f"salto {pair_norm}: max trade contemporanei ({max_sim})")
            return None
    sig["userId"] = uid
    sig["pair"] = pair_norm
    sig["isTest"] = False
    sig.pop("id", None)
    sig.setdefault("stopLossAdjustmentCount", 0)
    sig["stopLossAdjustmentCount"] = _int_from_firestore_field(sig.get("stopLossAdjustmentCount"))
    sig["createdAt"] = firestore.SERVER_TIMESTAMP
    ref = get_db().collection("signals").document()
    ref.set(sig)
    logs.append(f"signal live id={ref.id} pair={pair_norm}")
    return ref.id


@https_fn.on_call(cors=CorsOptions(cors_origins="*"))
def run_live_signals_from_capital(req: https_fn.CallableRequest) -> dict[str, Any]:
    """
    Scarica OHLC da Capital.com (/api/v1/prices) per i timeframe in strategy_configs,
    allinea i ruoli come run_backtest, genera segnali con _generate_test_signals e salva su `signals`
    solo quelli relativi all’ultima barra (live).
    """
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Autenticazione richiesta.",
        )
    uid = req.auth.uid
    data = dict(_callable_data(req))
    pairs_raw = data.get("pairs")
    if isinstance(pairs_raw, list) and pairs_raw:
        pairs = [_normalize_pair_symbols(str(p)) for p in pairs_raw if str(p).strip()]
        pairs = [p for p in pairs if p]
    else:
        pairs = ["EURUSD", "GBPUSD", "GBPJPY"]
    if not pairs:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Lista pairs vuota.",
        )
    max_points = int(data.get("maxBars") or data.get("max") or 400)
    max_points = max(50, min(max_points, 1000))

    snap_creds = get_db().collection("capital_credentials").document(uid).get()
    if not snap_creds.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.FAILED_PRECONDITION,
            message="Credenziali Capital.com assenti.",
        )
    creds = snap_creds.to_dict() or {}
    try:
        api_key = _decrypt_field(str(creds.get("apiKey", "")))
        login = _decrypt_field(str(creds.get("login", "")))
        password = _decrypt_field(str(creds.get("password", "")))
    except (InvalidToken, ValueError, TypeError) as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Decrypt capital_credentials: {e}",
        )

    snap_cfg = get_db().collection("strategy_configs").document(uid).get()
    raw_doc = snap_cfg.to_dict() if snap_cfg.exists else {}
    logs: list[str] = ["--- run_live_signals_from_capital ---"]
    errors: list[str] = []
    saved: list[dict[str, Any]] = []
    if not raw_doc:
        return {"ok": False, "saved": saved, "logs": logs + ["strategy_configs assente"], "errors": ["no_strategy"]}

    slots = _strategy_timeframe_slots(raw_doc)
    if not slots:
        return {"ok": False, "saved": saved, "logs": logs + ["nessun timeframe"], "errors": ["no_timeframes"]}

    strategy_eval = _strategy_with_defaults(raw_doc)

    for pair in pairs:
        try:
            df_by_role = _live_capital_df_by_role(
                uid, api_key, login, password, pair, slots, max_points, logs
            )
            if not df_by_role:
                errors.append(f"{pair}:no_role_data")
                continue
            aligned = _align_role_frames(df_by_role, strategy_eval, pair)
            if aligned is None or aligned.empty or len(aligned) < 3:
                errors.append(f"{pair}:aligned_empty")
                continue
            generated, gen_logs = _generate_test_signals(
                uid, pair, aligned, strategy_eval, is_test=False
            )
            logs.extend(gen_logs)
            last_bar_sigs = _filter_signals_to_last_execution_bar(generated, aligned)
            for sig in last_bar_sigs:
                sid = _persist_live_signal_doc(uid, sig, logs)
                if sid:
                    saved.append({"pair": pair, "id": sid})
        except Exception as e:
            _logger.exception("run_live_signals_from_capital pair=%s", pair)
            errors.append(f"{pair}:{e}")
            logs.append(f"errore {pair}: {e}")

    return {
        "ok": len(errors) == 0 or len(saved) > 0,
        "saved": saved,
        "logs": logs,
        "errors": errors,
    }


@https_fn.on_call(cors=CorsOptions(cors_origins="*"))
def save_live_signal(req: https_fn.CallableRequest) -> dict[str, Any]:
    """
    Crea un documento in `signals` (live) rispettando strategy_configs.exitRules.maxSimultaneousTrades
    per utente e coppia. Preferibile rispetto alla scrittura diretta Firestore (UX: errore esplicito).
    """
    if req.auth is None:
        raise HttpsError(FunctionsErrorCode.UNAUTHENTICATED, "Autenticazione richiesta")
    uid = req.auth.uid
    raw = dict(_callable_data(req))
    body_uid = raw.get("userId")
    if body_uid not in (None, "", uid):
        raise HttpsError(FunctionsErrorCode.PERMISSION_DENIED, "userId non coerente col token")
    pair_norm = _normalize_pair_symbols(str(raw.get("pair") or ""))
    if not pair_norm:
        raise HttpsError(FunctionsErrorCode.INVALID_ARGUMENT, "pair obbligatorio")

    snap_cfg = get_db().collection("strategy_configs").document(uid).get()
    exit_rules = (snap_cfg.to_dict() or {}).get("exitRules") or {}
    max_sim = _exit_rules_max_simultaneous(exit_rules)
    if max_sim < 10**6:
        open_n = _count_open_live_signals(uid, pair_norm, limit_scan=500)
        if open_n >= max_sim:
            raise HttpsError(
                FunctionsErrorCode.FAILED_PRECONDITION,
                f"massimo trade contemporanei raggiunto ({max_sim}) per {pair_norm}",
            )

    raw["userId"] = uid
    raw["pair"] = pair_norm
    raw["isTest"] = False
    raw.pop("id", None)
    raw.setdefault("stopLossAdjustmentCount", 0)
    raw["stopLossAdjustmentCount"] = _int_from_firestore_field(raw.get("stopLossAdjustmentCount"))
    raw["createdAt"] = firestore.SERVER_TIMESTAMP
    ref = get_db().collection("signals").document()
    ref.set(raw)
    return {"ok": True, "id": ref.id}


def _user_fcm_tokens(uid: str) -> list[str]:
    snap = get_db().collection("users").document(uid).get()
    if not snap.exists:
        return []
    d = snap.to_dict() or {}
    raw = d.get("fcmTokens")
    if not isinstance(raw, list):
        return []
    return [str(t) for t in raw if isinstance(t, str) and len(t) > 24][:24]


def _send_fcm_to_tokens(
    title: str,
    body: str,
    data: dict[str, str],
    tokens: list[str],
) -> None:
    for tok in tokens:
        msg = messaging.Message(
            notification=messaging.Notification(title=title[:80], body=body[:400]),
            data={k: str(v)[:1024] for k, v in data.items()},
            token=tok,
        )
        try:
            messaging.send(msg)
        except Exception as e:
            _logger.warning("FCM send fallita: %s", e)


def _sig_timestamp_to_utc_datetime(raw: Any) -> datetime | None:
    """Normalizza `timestamp` del segnale (Firestore / pandas) in datetime UTC aware."""
    if raw is None:
        return None
    try:
        if hasattr(raw, "timestamp") and callable(getattr(raw, "timestamp")):
            return datetime.fromtimestamp(float(raw.timestamp()), tz=timezone.utc)
    except Exception:
        pass
    try:
        ts = pd.Timestamp(raw)
        if ts.tzinfo is None:
            ts = ts.tz_localize("UTC")
        else:
            ts = ts.tz_convert("UTC")
        return ts.to_pydatetime()
    except Exception:
        return None


def _opening_label_for_sl_notification(sig: dict[str, Any]) -> str:
    pair = _normalize_pair_symbols(str(sig.get("pair") or "PAIR"))
    dt = _sig_timestamp_to_utc_datetime(sig.get("timestamp"))
    if dt is None:
        return f"{pair} · apertura (data non disponibile)"
    return f"{pair} · apertura {dt.strftime('%Y-%m-%d %H:%M:%S')} UTC"


def _live_sl_attach_pnl_spread_fields(
    sig: dict[str, Any],
    entry_px: float,
    exit_px: float,
    exit_cfg: dict[str, Any],
    entry_row: pd.Series | None,
    exit_row: pd.Series | None,
) -> dict[str, Any]:
    """Campi economici uscita (stessa logica della simulazione 1m) per aggiornamento Firestore."""
    pair_n = _normalize_pair_symbols(str(sig.get("pair", "")))
    sp = _split_fx_pair(pair_n)
    q_ccy = str(sig.get("quoteCurrency") or (sp[1] if sp else "USD"))
    pip_sz = _pip_size_for_quote(q_ccy)
    lots = float(sig.get("minLotPerTrade") or exit_cfg.get("minLotPerTrade", 0.01))
    if lots < 0.01:
        lots = 0.01
    contract = float(sig.get("fxContractUnitsPerLot") or _FX_UNITS_PER_LOT)
    if str(sig.get("type", "buy")).lower() == "buy":
        rp = float(_price_diff_to_pips(exit_px - entry_px, q_ccy))
    else:
        rp = float(_price_diff_to_pips(entry_px - exit_px, q_ccy))
    pnl_q = float(lots * contract * rp * pip_sz)
    pnl_eur, note = _pnl_quote_to_euro(pnl_q, q_ccy, pair_n, entry_px)
    out: dict[str, Any] = {
        "realizedPips": rp,
        "profitQuoteCurrency": float(pnl_q),
        "quoteCurrency": q_ccy,
        "realizedPnlEuro": float(pnl_eur),
        "pnlConversionNote": f"{note}; P&L {q_ccy} = minLot×{contract:.0f}×pips×pip_size ({rp} pips).",
    }
    if entry_row is None or exit_row is None:
        out.update(
            {
                "spreadEntryPips": 0.0,
                "spreadExitPips": 0.0,
                "spreadRoundTripPips": 0.0,
                "spreadPaidEuro": 0.0,
                "spreadNote": "barre_bid_ask_mancanti",
            }
        )
        return out
    se = _bar_spread_pips(entry_row, q_ccy)
    sx = _bar_spread_pips(exit_row, q_ccy)
    rt = (se + sx) / 2.0
    cost_quote = float(rt * pip_sz * lots * contract)
    eur_cost, snote = _pnl_quote_to_euro(cost_quote, q_ccy, pair_n, entry_px)
    out.update(
        {
            "spreadEntryPips": float(se),
            "spreadExitPips": float(sx),
            "spreadRoundTripPips": float(rt),
            "spreadPaidEuro": float(max(0.0, eur_cost)),
            "spreadNote": f"RT pips=(ingresso+uscita)/2 su barre 1m Bid+Ask; EUR~{snote}",
        }
    )
    return out


def _live_sl_process_open_signal(
    sig: dict[str, Any],
    df_1m: pd.DataFrame,
    exit_cfg: dict[str, Any],
    track_in: dict[str, Any] | None,
) -> dict[str, Any]:
    """
    Avanza SL / chiusura su barre 1m (stessa logica del backtest `_simulate_single`).
    Ritorna dict con chiavi:
      `closed` (bool), `firestore` (patch dict), `fcm_sl` (dict|None), `fcm_close` (dict|None),
      `new_track` (dict|None) se non chiuso.
    """
    empty = {"closed": False, "firestore": {}, "fcm_sl": None, "fcm_close": None, "new_track": None}
    if df_1m is None or df_1m.empty:
        return empty

    df = df_1m.copy()
    df["datetime"] = pd.to_datetime(df["datetime"], utc=True)
    df = df.sort_values("datetime").reset_index(drop=True)

    dt_ns = df["datetime"].to_numpy(dtype="datetime64[ns]").astype(np.int64, copy=False)
    hb = df["high_bid"].to_numpy(dtype=np.float64, copy=False)
    lb = df["low_bid"].to_numpy(dtype=np.float64, copy=False)
    ha = df["high_ask"].to_numpy(dtype=np.float64, copy=False)
    la = df["low_ask"].to_numpy(dtype=np.float64, copy=False)
    n_bars = int(len(df))

    be_cfg = exit_cfg.get("breakEven", {}) if isinstance(exit_cfg, dict) else {}
    tr_cfg = exit_cfg.get("trailingStop", {}) if isinstance(exit_cfg, dict) else {}
    be_active = bool(be_cfg.get("active", False))
    tr_active = bool(tr_cfg.get("active", False))
    if not be_active and not tr_active:
        return empty

    be_trigger_mult, be_lock_mult = _break_even_atr_mults(be_cfg)
    tr_act_mult, tr_step_mult = _trailing_stop_atr_mults(tr_cfg)

    ts_raw = sig.get("timestamp")
    ts = _to_utc_timestamp(ts_raw)
    side = str(sig.get("type", "buy")).lower()
    entry = float(sig.get("entryPrice") or 0.0)
    tp = float(sig.get("takeProfit") or 0.0)
    doc_sl = float(sig.get("stopLoss") or 0.0)

    track = dict(track_in) if isinstance(track_in, dict) else {}
    sl = float(track.get("stopLoss", doc_sl))
    be_done = bool(track.get("beDone", False))
    be_armed = bool(track.get("beArmed", False))
    trail_moved = bool(track.get("trailMoved", False))
    if side == "buy":
        peak_price = float(track.get("peakBid", entry))
        trough_price = float(entry)
    else:
        trough_price = float(track.get("troughAsk", entry))
        peak_price = float(entry)

    atr_entry = _signal_entry_atr(sig, exit_cfg)
    atr_e = float(atr_entry) if atr_entry is not None and atr_entry > 0 else 0.0
    tr_ok = bool(tr_active and atr_e > 0)
    be_ok = bool(be_active and atr_e > 0)
    trigger_be_px = float(be_trigger_mult * atr_e) if be_ok else 0.0
    lock_px = float(be_lock_mult * atr_e) if be_ok else 0.0
    trigger_ts_px = float(tr_act_mult * atr_e) if tr_ok else 0.0
    step_ts_px = float(tr_step_mult * atr_e) if tr_ok else 0.0

    ts_ns_sig = int(ts.value)
    ix_ge = int(np.searchsorted(dt_ns, ts_ns_sig, side="left"))
    entry_row_1m = df.iloc[ix_ge] if ix_ge < n_bars else None

    ts_ns_cut = ts_ns_sig
    last_bar_raw = track.get("lastProcessedBarTime")
    last_bar_ts: pd.Timestamp | None = None
    if last_bar_raw is not None:
        try:
            last_bar_ts = pd.Timestamp(last_bar_raw)
            if last_bar_ts.tzinfo is None:
                last_bar_ts = last_bar_ts.tz_localize("UTC")
            else:
                last_bar_ts = last_bar_ts.tz_convert("UTC")
        except Exception:
            last_bar_ts = None
    if last_bar_ts is not None:
        ts_ns_cut = max(ts_ns_cut, int(last_bar_ts.value))

    start_ix = int(np.searchsorted(dt_ns, ts_ns_cut, side="right"))
    if start_ix >= n_bars:
        return empty

    base_sl_adj = _int_from_firestore_field(sig.get("stopLossAdjustmentCount"))
    sl_adj_delta = 0
    sl_start = float(sl)
    closed = False
    exit_reason = ""
    exit_price = 0.0
    exit_bar_time: pd.Timestamp | None = None
    exit_row: pd.Series | None = None

    for j in range(start_ix, n_bars):
        high_bid = float(hb[j])
        low_bid = float(lb[j])
        high_ask = float(ha[j])
        low_ask = float(la[j])
        bar_time = pd.Timestamp(int(dt_ns[j]), unit="ns", tz="UTC")

        if side == "buy":
            peak_price = max(peak_price, high_bid)
            profitto_corrente = high_bid - entry
            profitto_massimo = peak_price - entry
            if be_ok and (not be_done) and profitto_corrente >= trigger_be_px and sl < entry:
                old_sl = sl
                new_sl = max(sl, entry + lock_px)
                if _sl_price_moved(old_sl, new_sl, entry):
                    sl_adj_delta += 1
                sl = new_sl
                be_done = True
                be_armed = True
            if tr_ok and profitto_massimo >= trigger_ts_px:
                livello_ts = peak_price - trigger_ts_px
                if livello_ts > sl + step_ts_px:
                    old_sl = sl
                    if _sl_price_moved(old_sl, livello_ts, entry):
                        sl_adj_delta += 1
                    sl = livello_ts
                    trail_moved = True
            sl_hit = low_bid <= sl
            tp_hit = high_bid >= tp
            if sl_hit or tp_hit:
                exit_price = float(sl if sl_hit else tp)
                exit_reason = (
                    ("SL_TRAIL" if trail_moved else ("SL_BE" if be_armed else "SL"))
                    if sl_hit
                    else "TP"
                )
                exit_bar_time = bar_time
                exit_row = df.iloc[j]
                closed = True
                break
        else:
            trough_price = min(trough_price, low_ask)
            profitto_corrente = entry - low_ask
            profitto_massimo = entry - trough_price
            if be_ok and (not be_done) and profitto_corrente >= trigger_be_px and sl > entry:
                old_sl = sl
                new_sl = min(sl, entry - lock_px)
                if _sl_price_moved(old_sl, new_sl, entry):
                    sl_adj_delta += 1
                sl = new_sl
                be_done = True
                be_armed = True
            if tr_ok and profitto_massimo >= trigger_ts_px:
                livello_ts = trough_price + trigger_ts_px
                if livello_ts < sl - step_ts_px:
                    old_sl = sl
                    if _sl_price_moved(old_sl, livello_ts, entry):
                        sl_adj_delta += 1
                    sl = livello_ts
                    trail_moved = True
            sl_hit = high_ask >= sl
            tp_hit = low_ask <= tp
            if sl_hit or tp_hit:
                exit_price = float(sl if sl_hit else tp)
                exit_reason = (
                    ("SL_TRAIL" if trail_moved else ("SL_BE" if be_armed else "SL"))
                    if sl_hit
                    else "TP"
                )
                exit_bar_time = bar_time
                exit_row = df.iloc[j]
                closed = True
                break

    last_path_ts = pd.Timestamp(int(dt_ns[n_bars - 1]), unit="ns", tz="UTC")
    opening = _opening_label_for_sl_notification(sig)
    pair_u = _normalize_pair_symbols(str(sig.get("pair") or ""))

    if closed and exit_bar_time is not None and exit_row is not None:
        econ = _live_sl_attach_pnl_spread_fields(
            sig, entry, exit_price, exit_cfg, entry_row_1m, exit_row
        )
        odt_close = _sig_timestamp_to_utc_datetime(sig.get("timestamp"))
        open_utc_close = odt_close.strftime("%Y-%m-%dT%H:%M:%SZ") if odt_close else ""
        fcm_close = {
            "title": "Segnale chiuso (simulazione 1m)",
            "body": f"{opening} · {exit_reason} @ {exit_price:.5f}",
            "data": {
                "type": "live_signal_closed",
                "pair": pair_u,
                "signalId": str(sig.get("_docId") or ""),
                "exitReason": exit_reason,
                "openUtc": open_utc_close,
            },
        }

        patch: dict[str, Any] = {
            "exitTime": exit_bar_time.to_pydatetime(),
            "exitPrice": exit_price,
            "exitReason": exit_reason,
            "liveSlTrack": firestore.DELETE_FIELD,
            "liveSlUpdatedAt": firestore.SERVER_TIMESTAMP,
            "stopLossAdjustmentCount": base_sl_adj + sl_adj_delta,
        }
        patch.update(econ)
        return {"closed": True, "firestore": patch, "fcm_sl": None, "fcm_close": fcm_close, "new_track": None}

    eps = max(1e-9, abs(entry) * 1e-8)
    sl_changed = abs(sl - sl_start) > eps
    new_track: dict[str, Any] = {
        "lastProcessedBarTime": last_path_ts.to_pydatetime(),
        "stopLoss": float(sl),
        "beDone": be_done,
        "beArmed": be_armed,
        "trailMoved": trail_moved,
        "peakBid": float(peak_price) if side == "buy" else float(entry),
        "troughAsk": float(trough_price) if side == "sell" else float(entry),
    }
    patch2: dict[str, Any] = {
        "liveSlTrack": new_track,
        "liveSlUpdatedAt": firestore.SERVER_TIMESTAMP,
        "stopLossAdjustmentCount": base_sl_adj + sl_adj_delta,
    }
    fcm_sl = None
    odt_sl = _sig_timestamp_to_utc_datetime(sig.get("timestamp"))
    open_utc_sl = odt_sl.strftime("%Y-%m-%dT%H:%M:%SZ") if odt_sl else ""
    if sl_changed:
        if sig.get("initialStopLoss") is None:
            patch2["initialStopLoss"] = float(doc_sl)
        patch2["previousStopLoss"] = float(sl_start)
        patch2["stopLoss"] = float(sl)
        fcm_sl = {
            "title": "Stop loss aggiornato",
            "body": (
                f"{opening} · nuovo SL {sl:.5f} (precedente {sl_start:.5f}). "
                "Aggiorna anche l’ordine su Capital.com se necessario."
            ),
            "data": {
                "type": "live_sl_updated",
                "pair": pair_u,
                "signalId": str(sig.get("_docId") or ""),
                "newSl": f"{sl:.8f}",
                "prevSl": f"{sl_start:.8f}",
                "openUtc": open_utc_sl,
            },
        }
    return {
        "closed": False,
        "firestore": patch2,
        "fcm_sl": fcm_sl,
        "fcm_close": None,
        "new_track": new_track,
    }


def _scheduled_live_sl_tick() -> None:
    if (os.environ.get("STRIKEZONE_DISABLE_LIVE_SL_SCHEDULER") or "").strip().lower() in (
        "1",
        "true",
        "yes",
    ):
        return

    db = get_db()
    creds_col = db.collection("capital_credentials")
    uids: list[str] = []
    for doc in creds_col.stream():
        if doc.id:
            uids.append(doc.id)
    if not uids:
        return

    pairs_watch = ("EURUSD", "GBPUSD", "GBPJPY")
    for uid in uids:
        snap_creds = creds_col.document(uid).get()
        if not snap_creds.exists:
            continue
        creds = snap_creds.to_dict() or {}
        try:
            api_key = _decrypt_field(str(creds.get("apiKey", "")))
            login = _decrypt_field(str(creds.get("login", "")))
            password = _decrypt_field(str(creds.get("password", "")))
        except Exception:
            _logger.warning("live_sl scheduler: skip uid=%s decrypt creds", uid)
            continue

        snap_cfg = db.collection("strategy_configs").document(uid).get()
        raw_cfg = snap_cfg.to_dict() if snap_cfg.exists else {}
        exit_rules = raw_cfg.get("exitRules") if isinstance(raw_cfg.get("exitRules"), dict) else {}
        be_raw = exit_rules.get("breakEven")
        tr_raw = exit_rules.get("trailingStop")
        be_on = bool(isinstance(be_raw, dict) and be_raw.get("active"))
        tr_on = bool(isinstance(tr_raw, dict) and tr_raw.get("active"))
        if not be_on and not tr_on:
            continue

        for pair in pairs_watch:
            q = (
                db.collection("signals")
                .where("userId", "==", uid)
                .where("pair", "==", pair)
                .order_by("timestamp", direction=firestore.Query.DESCENDING)
                .limit(40)
            )
            open_sigs: list[tuple[Any, dict[str, Any]]] = []
            for doc in q.stream():
                d = doc.to_dict() or {}
                if d.get("isTest") is True:
                    continue
                if not _signal_firestore_doc_is_open(d):
                    continue
                d = dict(d)
                d["_docId"] = doc.id
                open_sigs.append((doc.reference, d))
            if not open_sigs:
                continue

            logs: list[str] = []
            df_1m = _fetch_capital_prices_merged(
                uid, api_key, login, password, pair, "MINUTE", 1000, logs
            )
            if df_1m.empty:
                _logger.info("live_sl scheduler: no 1m data uid=%s pair=%s logs=%s", uid, pair, logs[:3])
                continue

            for ref, sig_data in open_sigs:
                try:
                    res = _live_sl_process_open_signal(sig_data, df_1m, exit_rules, sig_data.get("liveSlTrack"))
                    patch = res.get("firestore") or {}
                    if not patch:
                        continue
                    ref.update(patch)
                    tokens = _user_fcm_tokens(uid)
                    if not tokens:
                        continue
                    if res.get("fcm_sl"):
                        fc = res["fcm_sl"]
                        _send_fcm_to_tokens(
                            fc["title"],
                            fc["body"],
                            fc.get("data") or {},
                            tokens,
                        )
                    if res.get("fcm_close"):
                        fc = res["fcm_close"]
                        _send_fcm_to_tokens(
                            fc["title"],
                            fc["body"],
                            fc.get("data") or {},
                            tokens,
                        )
                except Exception as e:
                    _logger.warning("live_sl scheduler: uid=%s sig=%s err=%s", uid, sig_data.get("_docId"), e)


@scheduler_fn.on_schedule(
    schedule="* * * * *",
    timezone=scheduler_fn.Timezone("UTC"),
    memory=512,
    timeout_sec=300,
)
def scheduled_update_live_signals_sl(event: scheduler_fn.ScheduledEvent) -> None:
    """
    Ogni minuto (UTC): aggiorna SL su segnali live aperti se break-even e/o trailing sono attivi.
    """
    _ = event
    try:
        _scheduled_live_sl_tick()
    except Exception as e:
        _logger.exception("scheduled_update_live_signals_sl: %s", e)


@firestore_fn.on_document_created(document="signals/{signalId}")
def on_signal_document_created(event: firestore_fn.Event) -> None:
    """
    Unico trigger su `signals/{signalId}`: prima enforcement max posizioni (stesso criterio del backtest),
    poi notifica FCM. Due decorator separati sullo stesso path possono fallire al deploy Gen2 (Eventarc).
    """
    snap = event.data
    if snap is None:
        return
    data = snap.to_dict() or {}
    if data.get("isTest") is True:
        return

    uid_raw = data.get("userId")
    pair_norm = _normalize_pair_symbols(str(data.get("pair") or ""))
    signal_id = event.params.get("signalId")
    if uid_raw and pair_norm and signal_id:
        cfg_snap = get_db().collection("strategy_configs").document(str(uid_raw)).get()
        exit_rules = (cfg_snap.to_dict() or {}).get("exitRules") or {}
        max_sim = _exit_rules_max_simultaneous(exit_rules)
        if max_sim < 10**6:
            others = _count_open_live_signals(
                str(uid_raw), pair_norm, exclude_doc_id=str(signal_id), limit_scan=500
            )
            if others >= max_sim:
                snap.reference.delete()
                _logger.info(
                    "signals live: eliminato %s (maxSimultaneousTrades=%s pair=%s altri_aperti=%s)",
                    signal_id,
                    max_sim,
                    pair_norm,
                    others,
                )
                return

    uid = str(data.get("userId") or "").strip()
    if not uid:
        return
    pair = str(data.get("pair") or "PAIR").upper()
    sig_type = str(data.get("type") or "").upper()
    score = data.get("score")
    score_s = f"{float(score):.1f}" if isinstance(score, (int, float)) else ""

    tokens = _user_fcm_tokens(uid)
    if not tokens:
        _logger.info("notify live signal: nessun FCM token per uid=%s", uid)
        return

    _send_fcm_to_tokens(
        title="Nuovo segnale Strikezone",
        body=f"{pair} {sig_type} · score {score_s}".strip(),
        data={
            "type": "live_signal",
            "pair": pair,
            "signalId": str(event.params.get("signalId") or ""),
        },
        tokens=tokens,
    )

    cfg_snap = get_db().collection("strategy_configs").document(uid).get()
    raw_cfg = cfg_snap.to_dict() or {}
    exit_rules = raw_cfg.get("exitRules") if isinstance(raw_cfg.get("exitRules"), dict) else {}
    be = exit_rules.get("breakEven") if isinstance(exit_rules.get("breakEven"), dict) else {}
    tr = exit_rules.get("trailingStop") if isinstance(exit_rules.get("trailingStop"), dict) else {}
    be_on = bool(be.get("active"))
    tr_on = bool(tr.get("active"))
    if be_on and tr_on:
        _send_fcm_to_tokens(
            title="Aggiorna lo stop loss",
            body=(
                "Break-even e trailing stop sono attivi sulla tua strategia: "
                "monitora il mercato e aggiorna manualmente lo SL sulla piattaforma di trading "
                "(Capital.com non riceve ancora modifiche SL da questa app)."
            ),
            data={
                "type": "manual_sl_reminder",
                "pair": pair,
                "signalId": str(event.params.get("signalId") or ""),
            },
            tokens=tokens,
        )


@https_fn.on_request()
def get_strategy_config(req: https_fn.Request) -> https_fn.Response:
    """
    GET: restituisce il documento strategy_configs/{uid} dell'utente autenticato.
    Se il documento non esiste, body JSON {} (stesso comportamento atteso dal client: config assente).
    """
    headers = cors_headers(req)
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=headers)

    try:
        uid = verify_token(req)
    except ValueError as e:
        return https_fn.Response(json.dumps({"error": str(e)}), status=401, headers=headers)
    except Exception as e:
        return https_fn.Response(json.dumps({"error": str(e)}), status=401, headers=headers)

    if req.method != "GET":
        return https_fn.Response(
            json.dumps({"error": "Usa GET"}),
            status=405,
            headers=headers,
        )

    snap = get_db().collection("strategy_configs").document(uid).get()
    if not snap.exists:
        return https_fn.Response(json.dumps({}), status=200, headers=headers)

    data = snap.to_dict() or {}
    payload = _serialize_strategy_doc(data)
    return https_fn.Response(json.dumps(payload, ensure_ascii=False), status=200, headers=headers)


@https_fn.on_request()
def save_strategy_config(req: https_fn.Request) -> https_fn.Response:
    """
    POST: body JSON con timeframes, indicators, filters, exitRules (come da app).
    Scrive strategy_configs/{uid} con merge. userId e updatedAt impostati lato server.
    """
    headers = cors_headers(req)
    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=headers)

    try:
        uid = verify_token(req)
    except ValueError as e:
        return https_fn.Response(json.dumps({"error": str(e)}), status=401, headers=headers)
    except Exception as e:
        return https_fn.Response(json.dumps({"error": str(e)}), status=401, headers=headers)

    if req.method != "POST":
        return https_fn.Response(json.dumps({"error": "Usa POST"}), status=405, headers=headers)

    body = parse_request_json(req)
    if not body:
        return https_fn.Response(
            json.dumps({"error": "Body JSON vuoto o non valido"}),
            status=400,
            headers=headers,
        )

    payload = _sanitize_strategy_payload(body)
    if not payload:
        return https_fn.Response(
            json.dumps(
                {
                    "error": "Nessun campo strategia valido. "
                    "Invia almeno uno tra: timeframes, indicators, filters, exitRules",
                }
            ),
            status=400,
            headers=headers,
        )

    payload["userId"] = uid
    payload["updatedAt"] = firestore.SERVER_TIMESTAMP

    get_db().collection("strategy_configs").document(uid).set(payload, merge=True)

    return https_fn.Response(
        json.dumps({"ok": True, "userId": uid}),
        status=200,
        headers=headers,
    )
