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
