import os
from pathlib import Path

# Base paths
BASE_DIR = Path(__file__).parent.parent
DOMAINS_DIR = BASE_DIR / "domains"
LOGS_DIR = BASE_DIR / "logs"
CONFIG_DIR = BASE_DIR / "config"

# Pi-hole database path
PIHOLE_DB_PATH = os.getenv('PIHOLE_DB_PATH', '/etc/pihole/pihole-FTL.db')

# Category sources with backup URLs
CATEGORY_SOURCES = {
    "social": [
        "https://raw.githubusercontent.com/cbuijs/shallalist/master/social.txt",
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social-only/hosts"
    ],
    "porn": [
        "https://raw.githubusercontent.com/cbuijs/shallalist/master/porn.txt",
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts"
    ],
    "malware": [
        "https://raw.githubusercontent.com/cbuijs/shallalist/master/malware.txt",
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/malware-only/hosts"
    ],
    "gambling": [
        "https://raw.githubusercontent.com/cbuijs/shallalist/master/gambling.txt"
    ],
    "ads": [
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/adware-malware/hosts"
    ]
}

# Device mapping (can be overridden by devices.json)
DEFAULT_DEVICE_MAP = {
    "192.168.1.10": "Dad-Laptop",
    "192.168.1.11": "Kid-Tablet",
    "192.168.1.12": "TV",
    "192.168.1.1": "Router"
}

# Dashboard settings
DASHBOARD_HOST = os.getenv('DASHBOARD_HOST', '0.0.0.0')
DASHBOARD_PORT = int(os.getenv('DASHBOARD_PORT', 8080))
DASHBOARD_TITLE = "Pi-hole Network Monitor"

# Logging settings
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
LOG_FILE = LOGS_DIR / 'application.log'

# Update intervals (in hours)
DOMAIN_UPDATE_INTERVAL = 24
LOG_PARSE_INTERVAL = 1

# Retention settings (in days)
LOG_RETENTION_DAYS = 30
REPORT_RETENTION_DAYS = 90
