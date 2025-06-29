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
