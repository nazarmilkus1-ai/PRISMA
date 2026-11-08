import os
from urllib.parse import urlparse
from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()

def _required(name: str) -> str:
    value = os.getenv(name, '').strip()
    if not value:
        raise RuntimeError(f'Missing required environment variable: {name}')
    if value in {'CHANGE_ME', 'REPLACE_ME'} or value.startswith('YOUR_'):
        raise RuntimeError(f'Environment variable {name} still contains a placeholder')
    return value

def _required_url(name: str) -> str:
    value = _required(name).rstrip('/')
    parsed = urlparse(value)
    if parsed.scheme not in {'http', 'https'} or not parsed.netloc:
        raise RuntimeError(f'{name} must be a valid http(s) URL')
    return value

def _optional_int(name: str) -> int:
    value = os.getenv(name, '').strip()
    if not value:
        return 0
    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(f'{name} must be an integer') from exc


def _optional_url(name: str) -> str:
    value = os.getenv(name, '').strip().rstrip('/')
    if not value:
        return ''
    parsed = urlparse(value)
    hostname = (parsed.hostname or '').lower()
    placeholder_hosts = {'твій-домен', 'your-domain', 'example.com', 'localhost'}
    if parsed.scheme not in {'http', 'https'} or not parsed.netloc or hostname in placeholder_hosts or '.' not in hostname:
        print(f'Warning: ignoring invalid optional URL {name}')
        return ''
    return value

BOT_TOKEN = _required('BOT_TOKEN')
SUPABASE_URL = _required_url('SUPABASE_URL')
# Prefer the explicit server-only variable. Keep SUPABASE_KEY as a legacy
# compatibility alias because existing Render deployments may still use it.
SUPABASE_KEY = _required('SUPABASE_SERVICE_ROLE_KEY') if os.getenv('SUPABASE_SERVICE_ROLE_KEY') else _required('SUPABASE_KEY')
if SUPABASE_KEY.startswith(('sb_publishable_', 'sb_anon_')):
    raise RuntimeError('Supabase server client received a publishable/anon key; configure the legacy service_role key as SUPABASE_SERVICE_ROLE_KEY')
if len(SUPABASE_KEY) < 32:
    raise RuntimeError('Supabase server key is too short to be valid')
REDIS_URL = os.getenv('REDIS_URL', '').strip()
REDIS_TOKEN = os.getenv('REDIS_TOKEN', '').strip()
PRISMA_ENV = os.getenv('PRISMA_ENV', 'development').strip().lower()

PLUGIN_API_URL = _optional_url('PLUGIN_API_URL')
PLUGIN_API_KEY = os.getenv('PLUGIN_API_KEY', '').strip()
OWNER_TG_ID = _optional_int('OWNER_TG_ID')
ADMIN_GROUP_ID = _optional_int('ADMIN_GROUP_ID')
MODERATION_GROUP_ID = _optional_int('MODERATION_GROUP_ID')
PANEL_URL = _optional_url('PANEL_URL')
SITE_URL = _optional_url('SITE_URL') or _optional_url('NEXT_PUBLIC_SITE_URL') or 'https://prisma-fawn-seven.vercel.app'
MINECRAFT_HOST = os.getenv('MINECRAFT_HOST', '').strip()
MINECRAFT_JAVA_ADDRESS = os.getenv('MINECRAFT_JAVA_ADDRESS', '').strip() or os.getenv('NEXT_PUBLIC_JAVA_ADDRESS', '').strip()
MINECRAFT_BEDROCK_ADDRESS = os.getenv('MINECRAFT_BEDROCK_ADDRESS', '').strip() or os.getenv('NEXT_PUBLIC_BEDROCK_ADDRESS', '').strip()
MINECRAFT_JAVA_PORT = _optional_int('MINECRAFT_JAVA_PORT') or 25575
MINECRAFT_BEDROCK_PORT = _optional_int('MINECRAFT_BEDROCK_PORT') or _optional_int('NEXT_PUBLIC_BEDROCK_PORT') or 18591
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO').upper()

supabase: Client = create_client(
    SUPABASE_URL,
    SUPABASE_KEY,
)
try:
    supabase.auth.set_session('', '')
except Exception:
    pass
