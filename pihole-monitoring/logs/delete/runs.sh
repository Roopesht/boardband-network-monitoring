#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_DIR="pihole-monitoring"
DOMAINS_DIR="$PROJECT_DIR/domains"
UTILS_DIR="$PROJECT_DIR/utils"
LOGS_DIR="$PROJECT_DIR/logs"
CONFIG_DIR="$PROJECT_DIR/config"
SCRIPTS_DIR="$PROJECT_DIR/scripts"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    if ! command -v pip3 &> /dev/null; then
        missing_deps+=("python3-pip")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        echo "Please install them first:"
        echo "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_deps[*]}"
        echo "  CentOS/RHEL: sudo yum install ${missing_deps[*]}"
        exit 1
    fi
    
    success "All dependencies found"
}

# Create virtual environment
setup_venv() {
    log "Setting up Python virtual environment..."
    
    if [ ! -d "$PROJECT_DIR/venv" ]; then
        python3 -m venv "$PROJECT_DIR/venv"
        success "Virtual environment created"
    else
        warning "Virtual environment already exists"
    fi
    
    # Activate venv and install packages
    source "$PROJECT_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install pandas nicegui requests python-dateutil schedule
    success "Python packages installed"
}

log "🚀 Setting up Enhanced Pi-hole Monitoring System..."

# Check if we're running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    warning "Running as root is not recommended for security reasons"
    read -p "Continue anyway? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

check_dependencies

log "📁 Creating folder structure..."
mkdir -p $DOMAINS_DIR $UTILS_DIR $LOGS_DIR $CONFIG_DIR $SCRIPTS_DIR

setup_venv

log "📄 Creating configuration file..."
cat > "$CONFIG_DIR/config.py" << 'EOF'
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
EOF

log "📄 Creating enhanced domain_updater.py..."
cat > "$PROJECT_DIR/domain_updater.py" << 'EOF'
import requests
import os
import json
import logging
from pathlib import Path
from datetime import datetime
import time
import sys

# Add config to path
sys.path.insert(0, str(Path(__file__).parent / 'config'))
from config import CATEGORY_SOURCES, DOMAINS_DIR, LOG_FILE, LOG_FORMAT, LOG_LEVEL

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format=LOG_FORMAT,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DomainUpdater:
    def __init__(self, domains_path=None, max_retries=3, timeout=30):
        self.domains_path = Path(domains_path) if domains_path else DOMAINS_DIR
        self.max_retries = max_retries
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (compatible; Pi-hole-Monitor/1.0)'
        })
        
    def download_with_retry(self, url, retries=None):
        """Download URL with retry logic and fallback handling"""
        if retries is None:
            retries = self.max_retries
            
        for attempt in range(retries):
            try:
                logger.info(f"Downloading from {url} (attempt {attempt + 1}/{retries})")
                response = self.session.get(url, timeout=self.timeout)
                response.raise_for_status()
                return response.text
            except requests.exceptions.RequestException as e:
                logger.warning(f"Attempt {attempt + 1} failed: {e}")
                if attempt < retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                else:
                    raise
        
    def process_hosts_file(self, content):
        """Process hosts file format and extract domains"""
        domains = set()
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            # Handle hosts file format (0.0.0.0 domain.com or 127.0.0.1 domain.com)
            parts = line.split()
            if len(parts) >= 2 and (parts[0] in ['0.0.0.0', '127.0.0.1']):
                domain = parts[1]
                if domain != 'localhost':
                    domains.add(domain)
            else:
                # Handle plain domain list
                domains.add(line)
        
        return domains
        
    def download_category(self, category, urls):
        """Download domains for a specific category with fallback URLs"""
        all_domains = set()
        success = False
        
        for url in urls:
            try:
                content = self.download_with_retry(url)
                domains = self.process_hosts_file(content)
                all_domains.update(domains)
                logger.info(f"Successfully downloaded {len(domains)} domains from {url}")
                success = True
                break  # Use first successful URL
            except Exception as e:
                logger.error(f"Failed to download from {url}: {e}")
                continue
        
        if not success:
            logger.error(f"All URLs failed for category {category}")
            return False
            
        # Save domains to file
        output_file = self.domains_path / f"{category}_domains.txt"
        try:
            with open(output_file, 'w') as f:
                for domain in sorted(all_domains):
                    f.write(f"{domain}\n")
            
            logger.info(f"Saved {len(all_domains)} {category} domains to {output_file}")
            return True
        except Exception as e:
            logger.error(f"Failed to save {category} domains: {e}")
            return False
    
    def update_all_lists(self):
        """Update all domain lists"""
        logger.info("Starting domain list update")
        self.domains_path.mkdir(parents=True, exist_ok=True)
        
        results = {}
        for category, urls in CATEGORY_SOURCES.items():
            logger.info(f"Updating {category} category...")
            results[category] = self.download_category(category, urls)
        
        # Save update metadata
        metadata = {
            'last_update': datetime.now().isoformat(),
            'results': results,
            'total_categories': len(CATEGORY_SOURCES),
            'successful_updates': sum(results.values())
        }
        
        metadata_file = self.domains_path / 'update_metadata.json'
        with open(metadata_file, 'w') as f:
            json.dump(metadata, f, indent=2)
        
        success_count = sum(results.values())
        logger.info(f"Update completed: {success_count}/{len(CATEGORY_SOURCES)} categories successful")
        
        if success_count == 0:
            logger.critical("All category updates failed!")
            return False
        elif success_count < len(CATEGORY_SOURCES):
            logger.warning(f"Partial success: {success_count}/{len(CATEGORY_SOURCES)} categories updated")
        
        return True

def main():
    updater = DomainUpdater()
    success = updater.update_all_lists()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
EOF

log "📄 Creating enhanced log_parser.py..."
cat > "$PROJECT_DIR/log_parser.py" << 'EOF'
import sqlite3
import pandas as pd
import json
import logging
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Set, Optional

# Add config to path
sys.path.insert(0, str(Path(__file__).parent / 'config'))
from config import (PIHOLE_DB_PATH, DOMAINS_DIR, DEFAULT_DEVICE_MAP, 
                   LOG_FILE, LOG_FORMAT, LOG_LEVEL, CONFIG_DIR)

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format=LOG_FORMAT,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class LogParser:
    def __init__(self, db_path=None, domains_dir=None):
        self.db_path = Path(db_path) if db_path else Path(PIHOLE_DB_PATH)
        self.domains_dir = Path(domains_dir) if domains_dir else DOMAINS_DIR
        self.categories = {}
        self.device_map = self._load_device_map()
        self._load_categories()
        
    def _load_device_map(self) -> Dict[str, str]:
        """Load device mapping from JSON file or use defaults"""
        devices_file = CONFIG_DIR / 'devices.json'
        try:
            if devices_file.exists():
                with open(devices_file) as f:
                    device_map = json.load(f)
                logger.info(f"Loaded {len(device_map)} device mappings from {devices_file}")
                return device_map
        except Exception as e:
            logger.warning(f"Failed to load device map: {e}")
        
        # Create default devices file
        try:
            devices_file.parent.mkdir(parents=True, exist_ok=True)
            with open(devices_file, 'w') as f:
                json.dump(DEFAULT_DEVICE_MAP, f, indent=2)
            logger.info(f"Created default device map at {devices_file}")
        except Exception as e:
            logger.error(f"Failed to create default device map: {e}")
            
        return DEFAULT_DEVICE_MAP.copy()
    
    def _load_categories(self):
        """Load domain categories from files"""
        if not self.domains_dir.exists():
            logger.warning(f"Domains directory {self.domains_dir} not found")
            return
            
        for domain_file in self.domains_dir.glob("*_domains.txt"):
            category = domain_file.stem.replace('_domains', '')
            try:
                with open(domain_file) as f:
                    domains = {line.strip() for line in f if line.strip() and not line.startswith('#')}
                self.categories[category] = domains
                logger.info(f"Loaded {len(domains)} {category} domains")
            except Exception as e:
                logger.error(f"Failed to load {domain_file}: {e}")
    
    def categorize_domain(self, domain: str) -> str:
        """Categorize a domain based on loaded categories"""
        domain = domain.lower().strip()
        
        for category, domains in self.categories.items():
            # Check exact match first
            if domain in domains:
                return category
            
            # Check subdomain matches
            for cat_domain in domains:
                if domain.endswith(f".{cat_domain}") or domain == cat_domain:
                    return category
        
        return "uncategorized"
    
    def check_db_connection(self) -> bool:
        """Check if Pi-hole database is accessible"""
        try:
            if not self.db_path.exists():
                logger.error(f"Pi-hole database not found at {self.db_path}")
                return False
                
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='queries'")
                if not cursor.fetchone():
                    logger.error("Queries table not found in database")
                    return False
                    
            logger.info("Database connection successful")
            return True
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            return False
    
    def parse_logs(self, days: int = 1, device_filter: Optional[str] = None) -> pd.DataFrame:
        """Parse Pi-hole logs with error handling and filtering"""
        if not self.check_db_connection():
            return pd.DataFrame()
        
        start_time = (datetime.now() - timedelta(days=days)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        
        query = """
        SELECT client, domain, timestamp, status
        FROM queries 
        WHERE timestamp >= ?
        ORDER BY timestamp DESC
        """
        
        try:
            with sqlite3.connect(self.db_path) as conn:
                df = pd.read_sql(query, conn, params=[int(start_time.timestamp())])
            
            if df.empty:
                logger.warning(f"No data found for the last {days} days")
                return df
            
            # Process the data
            df['Time'] = pd.to_datetime(df['timestamp'], unit='s')
            df['Device'] = df['client'].map(self.device_map).fillna(df['client'])
            df['Category'] = df['domain'].apply(self.categorize_domain)
            df['Hour'] = df['Time'].dt.hour
            df['Date'] = df['Time'].dt.date
            
            # Add status description
            status_map = {0: 'Unknown', 1: 'Blocked (gravity)', 2: 'Allowed', 3: 'Blocked (regex)', 
                         4: 'Blocked (exact)', 5: 'Blocked (CNAME)', 9: 'Blocked (gravity, CNAME)',
                         10: 'Blocked (regex, CNAME)', 11: 'Blocked (exact, CNAME)'}
            df['Status_Description'] = df['status'].map(status_map).fillna('Unknown')
            
            # Apply device filter if specified
            if device_filter:
                df = df[df['Device'].str.contains(device_filter, case=False, na=False)]
            
            logger.info(f"Parsed {len(df)} queries from last {days} days")
            return df
            
        except Exception as e:
            logger.error(f"Failed to parse logs: {e}")
            return pd.DataFrame()
    
    def generate_summary(self, df: pd.DataFrame) -> Dict:
        """Generate summary statistics"""
        if df.empty:
            return {}
        
        summary = {
            'total_queries': len(df),
            'unique_domains': df['domain'].nunique(),
            'unique_devices': df['Device'].nunique(),
            'date_range': {
                'start': df['Time'].min().isoformat(),
                'end': df['Time'].max().isoformat()
            },
            'top_categories': df['Category'].value_counts().head(10).to_dict(),
            'top_domains': df['domain'].value_counts().head(10).to_dict(),
            'device_activity': df['Device'].value_counts().to_dict(),
            'blocked_queries': len(df[df['status'] != 2]),
            'blocked_percentage': (len(df[df['status'] != 2]) / len(df) * 100) if len(df) > 0 else 0
        }
        
        return summary

def main():
    parser = LogParser()
    df = parser.parse_logs(days=1)
    
    if not df.empty:
        summary = parser.generate_summary(df)
        print(json.dumps(summary, indent=2, default=str))
    else:
        logger.error("No data to process")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

log "📄 Creating enhanced dashboard.py..."
cat > "$PROJECT_DIR/dashboard.py" << 'EOF'
import sys
import logging
from pathlib import Path
from datetime import datetime, timedelta
import pandas as pd
import json

# Add config to path
sys.path.insert(0, str(Path(__file__).parent / 'config'))
from config import DASHBOARD_HOST, DASHBOARD_PORT, DASHBOARD_TITLE, LOG_FILE, LOG_FORMAT, LOG_LEVEL

from nicegui import ui, app
from log_parser import LogParser

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format=LOG_FORMAT,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class Dashboard:
    def __init__(self):
        self.parser = LogParser()
        self.current_data = pd.DataFrame()
        self.last_update = None
        
    def load_data(self, days=1, device_filter=None):
        """Load and cache data"""
        try:
            self.current_data = self.parser.parse_logs(days=days, device_filter=device_filter)
            self.last_update = datetime.now()
            logger.info(f"Data loaded: {len(self.current_data)} records")
            return True
        except Exception as e:
            logger.error(f"Failed to load data: {e}")
            return False
    
    def create_summary_cards(self):
        """Create summary statistics cards"""
        if self.current_data.empty:
            return ui.card().classes('w-full').with_content(
                ui.label('No data available').classes('text-red-500')
            )
        
        summary = self.parser.generate_summary(self.current_data)
        
        with ui.row().classes('w-full gap-4'):
            # Total queries card
            with ui.card().classes('w-64'):
                ui.label('Total Queries').classes('text-lg font-bold')
                ui.label(f"{summary.get('total_queries', 0):,}").classes('text-2xl text-blue-600')
            
            # Blocked queries card
            with ui.card().classes('w-64'):
                ui.label('Blocked Queries').classes('text-lg font-bold')
                blocked = summary.get('blocked_queries', 0)
                percentage = summary.get('blocked_percentage', 0)
                ui.label(f"{blocked:,} ({percentage:.1f}%)").classes('text-2xl text-red-600')
            
            # Unique domains card
            with ui.card().classes('w-64'):
                ui.label('Unique Domains').classes('text-lg font-bold')
                ui.label(f"{summary.get('unique_domains', 0):,}").classes('text-2xl text-green-600')
            
            # Active devices card
            with ui.card().classes('w-64'):
                ui.label('Active Devices').classes('text-lg font-bold')
                ui.label(f"{summary.get('unique_devices', 0)}").classes('text-2xl text-purple-600')

def create_dashboard():
    dashboard = Dashboard()
    
    # Load initial data
    if not dashboard.load_data():
        ui.notify('Failed to load data. Check Pi-hole database connection.', type='negative')
    
    ui.page_title(DASHBOARD_TITLE)
    
    with ui.header().classes('bg-blue-600 text-white'):
        ui.label(DASHBOARD_TITLE).classes('text-xl font-bold')
        
        with ui.row().classes('ml-auto'):
            ui.label(f'Last updated: {dashboard.last_update.strftime("%H:%M:%S") if dashboard.last_update else "Never"}').classes('text-sm')
            ui.button('Refresh', on_click=lambda: refresh_data()).classes('ml-4')
    
    # Main content area
    with ui.column().classes('w-full p-4 space-y-4'):
        # Summary cards
        summary_container = ui.column().classes('w-full')
        
        # Filters
        with ui.card().classes('w-full'):
            ui.label('Filters').classes('text-lg font-bold mb-2')
            with ui.row().classes('gap-4'):
                days_select = ui.select([1, 7, 30], value=1, label='Days').classes('w-32')
                device_input = ui.input('Device Filter (optional)').classes('w-64')
                ui.button('Apply Filters', on_click=lambda: apply_filters()).classes('ml-4')
        
        # Tabs for different views
        with ui.tabs().classes('w-full') as tabs:
            overview_tab = ui.tab('Overview')
            categories_tab = ui.tab('Categories')
            devices_tab = ui.tab('Devices')
            blocked_tab = ui.tab('Blocked Content')
            timeline_tab = ui.tab('Timeline')
        
        with ui.tab_panels(tabs, value=overview_tab).classes('w-full'):
            # Overview panel
            with ui.tab_panel(overview_tab):
                overview_content = ui.column().classes('w-full')
            
            # Categories panel
            with ui.tab_panel(categories_tab):
                categories_content = ui.column().classes('w-full')
            
            # Devices panel
            with ui.tab_panel(devices_tab):
                devices_content = ui.column().classes('w-full')
            
            # Blocked content panel
            with ui.tab_panel(blocked_tab):
                blocked_content = ui.column().classes('w-full')
            
            # Timeline panel
            with ui.tab_panel(timeline_tab):
                timeline_content = ui.column().classes('w-full')
    
    def refresh_data():
        """Refresh dashboard data"""
        ui.notify('Refreshing data...', type='info')
        if dashboard.load_data(days_select.value, device_input.value if device_input.value else None):
            update_all_panels()
            ui.notify('Data refreshed successfully', type='positive')
        else:
            ui.notify('Failed to refresh data', type='negative')
    
    def apply_filters():
        """Apply selected filters"""
        refresh_data()
    
    def update_all_panels():
        """Update all dashboard panels"""
        # Clear existing content
        summary_container.clear()
        overview_content.clear()
        categories_content.clear()
        devices_content.clear()
        blocked_content.clear()
        timeline_content.clear()
        
        if dashboard.current_data.empty:
            for content in [overview_content, categories_content, devices_content, blocked_content, timeline_content]:
                with content:
                    ui.label('No data available for the selected filters').classes('text-gray-500 text-center p-8')
            return
        
        # Update summary cards
        with summary_container:
            dashboard.create_summary_cards()
        
        # Update overview
        with overview_content:
            ui.label('Query Overview').classes('text-xl font-bold mb-4')
            summary = dashboard.parser.generate_summary(dashboard.current_data)
            
            # Top domains table
            ui.label('Top Domains').classes('text-lg font-bold mt-4 mb-2')
            top_domains = list(summary.get('top_domains', {}).items())[:10]
            if top_domains:
                with ui.grid(columns=2).classes('w-full max-w-2xl'):
                    ui.label('Domain').classes('font-bold')
                    ui.label('Queries').classes('font-bold')
                    for domain, count in top_domains:
                        ui.label(domain)
                        ui.label(str(count))
        
        # Update categories
        with categories_content:
            ui.label('Category Breakdown').classes('text-xl font-bold mb-4')
            category_stats = dashboard.current_data['Category'].value_counts()
            
            with ui.grid(columns=2).classes('w-full max-w-2xl'):
                ui.label('Category').classes('font-bold')
                ui.label('Queries').classes('font-bold')
                for category, count in category_stats.head(10).items():
                    ui.label(category.title())
                    ui.label(str(count))
        
        # Update devices
        with devices_content:
            ui.label('Device Activity').classes('text-xl font-bold mb-4')
            device_stats = dashboard.current_data['Device'].value_counts()
            
            with ui.grid(columns=2).classes('w-full max-w-2xl'):
                ui.label('Device').classes('font-bold')
                ui.label('Queries').classes('font-bold')
                for device, count in device_stats.items():
                    ui.label(device)
                    ui.label(str(count))
        
        # Update blocked content
        with blocked_content:
            ui.label('Blocked Content').classes('text-xl font-bold mb-4')
            blocked_data = dashboard.current_data[dashboard.current_data['status'] != 2]
            
            if not blocked_data.empty:
                blocked_domains = blocked_data['domain'].value_counts().head(20)
                with ui.grid(columns=3).classes('w-full'):
                    ui.label('Domain').classes('font-bold')
                    ui.label('Blocks').classes('font-bold')
                    ui.label('Category').classes('font-bold')
                    for domain, count in blocked_domains.items():
                        category = dashboard.parser.categorize_domain(domain)
                        ui.label(domain)
                        ui.label(str(count))
                        ui.label(category.title())
            else:
                ui.label('No blocked content in selected time range').classes('text-gray-500')
        
        # Update timeline
        with timeline_content:
            ui.label('Query Timeline').classes('text-xl font-bold mb-4')
            hourly_stats = dashboard.current_data.groupby('Hour').size()
            
            ui.label('Queries by Hour').classes('text-lg font-bold mt-4 mb-2')
            with ui.grid(columns=2).classes('w-full max-w-md'):
                ui.label('Hour').classes('font-bold')
                ui.label('Queries').classes('font-bold')
                for hour, count in hourly_stats.items():
                    ui.label(f"{hour:02d}:00")
                    ui.label(str(count))
    
    # Initial panel update
    update_all_panels()

if __name__ == "__main__":
    logger.info(f"Starting dashboard on {DASHBOARD_HOST}:{DASHBOARD_PORT}")
    create_dashboard()
    ui.run(host=DASHBOARD_HOST, port=DASHBOARD_PORT, title=DASHBOARD_TITLE)
EOF

log "📄 Creating system monitoring script..."
cat > "$SCRIPTS_DIR/monitor.py" << 'EOF'
#!/usr/bin/env python3
"""
System monitoring and maintenance script
"""
import sys
import logging
import schedule
import time
from pathlib import Path
from datetime import datetime, timedelta
import json

# Add config to path
sys.path.insert(0, str(Path(__file__).parent.parent / 'config'))
from config import LOG_FILE, LOG_FORMAT, LOG_LEVEL, LOGS_DIR, LOG_RETENTION_DAYS

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format=LOG_FORMAT,
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def cleanup_old_logs():
    """Clean up old log files"""
    try:
        cutoff_date = datetime.now() - timedelta(days=LOG_RETENTION_DAYS)
        cleaned_count = 0
        
        for log_file in LOGS_DIR.glob('*.log'):
            if log_file.stat().st_mtime < cutoff_date.timestamp():
                log_file.unlink()
                cleaned_count += 1
        
        for report_file in LOGS_DIR.glob('report_*.txt'):
            if report_file.stat().st_mtime < cutoff_date.timestamp():
                report_file.unlink()
                cleaned_count += 1
        
        logger.info(f"Cleaned up {cleaned_count} old log files")
        return cleaned_count
    except Exception as e:
        logger.error(f"Failed to cleanup logs: {e}")
        return 0

def check_system_health():
    """Check system health and log status"""
    health_status = {
        'timestamp': datetime.now().isoformat(),
        'pihole_db_accessible': False,
        'domain_files_present': 0,
        'last_domain_update': None,
        'disk_usage': None
    }
    
    try:
        # Check Pi-hole database
        from log_parser import LogParser
        parser = LogParser()
        health_status['pihole_db_accessible'] = parser.check_db_connection()
        
        # Check domain files
        from config import DOMAINS_DIR
        domain_files = list(DOMAINS_DIR.glob('*_domains.txt'))
        health_status['domain_files_present'] = len(domain_files)
        
        # Check last domain update
        metadata_file = DOMAINS_DIR / 'update_metadata.json'
        if metadata_file.exists():
            with open(metadata_file) as f:
                metadata = json.load(f)
                health_status['last_domain_update'] = metadata.get('last_update')
        
        # Check disk usage
        import shutil
        total, used, free = shutil.disk_usage(LOGS_DIR)
        health_status['disk_usage'] = {
            'total_gb': total // (1024**3),
            'used_gb': used // (1024**3),
            'free_gb': free // (1024**3),
            'usage_percent': (used / total) * 100
        }
        
        logger.info(f"System health check completed: {health_status}")
        
        # Save health status
        health_file = LOGS_DIR / f'health_{datetime.now().strftime("%Y%m%d")}.json'
        with open(health_file, 'w') as f:
            json.dump(health_status, f, indent=2)
        
        return health_status
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return health_status

def update_domains():
    """Update domain lists"""
    try:
        from domain_updater import DomainUpdater
        updater = DomainUpdater()
        success = updater.update_all_lists()
        logger.info(f"Domain update {'successful' if success else 'failed'}")
        return success
    except Exception as e:
        logger.error(f"Domain update failed: {e}")
        return False

def generate_daily_report():
    """Generate daily activity report"""
    try:
        from log_parser import LogParser
        parser = LogParser()
        df = parser.parse_logs(days=1)
        
        if df.empty:
            logger.warning("No data for daily report")
            return False
        
        summary = parser.generate_summary(df)
        
        # Save report
        report_file = LOGS_DIR / f'daily_report_{datetime.now().strftime("%Y%m%d")}.json'
        with open(report_file, 'w') as f:
            json.dump(summary, f, indent=2, default=str)
        
        logger.info(f"Daily report generated: {len(df)} queries processed")
        return True
        
    except Exception as e:
        logger.error(f"Daily report generation failed: {e}")
        return False

def main():
    """Main monitoring loop"""
    logger.info("Starting Pi-hole monitoring system")
    
    # Schedule tasks
    schedule.every().day.at("02:00").do(update_domains)
    schedule.every().day.at("03:00").do(cleanup_old_logs)
    schedule.every().day.at("23:55").do(generate_daily_report)
    schedule.every().hour.do(check_system_health)
    
    # Run initial health check
    check_system_health()
    
    logger.info("Monitoring system started. Running scheduled tasks...")
    
    try:
        while True:
            schedule.run_pending()
            time.sleep(60)  # Check every minute
    except KeyboardInterrupt:
        logger.info("Monitoring system stopped by user")
    except Exception as e:
        logger.error(f"Monitoring system crashed: {e}")
        raise

if __name__ == "__main__":
    main()
EOF