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
