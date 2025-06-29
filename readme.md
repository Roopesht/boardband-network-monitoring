# Pi-hole Enhanced Monitoring System

A comprehensive monitoring and analytics dashboard for Pi-hole network-wide ad blocking with enhanced domain categorization, device tracking, and automated reporting.

## ⚠️ IMPORTANT NOTICE

**🏠 HOME USE ONLY - READ BEFORE INSTALLATION**

This Pi-hole monitoring system is designed and intended **exclusively for personal home networks**. 

### ✅ Appropriate Use:
- Personal home broadband connections
- Private residential networks
- Home lab environments
- Personal learning and development

### ❌ DO NOT USE FOR:
- **Corporate/Business networks** - May violate company IT policies and security protocols
- **Public WiFi networks** - Could interfere with legitimate network services and violate terms of service
- **Shared accommodation networks** - May affect other users without consent
- **Educational institution networks** - Often violates acceptable use policies
- **Any network you don't own or have explicit permission to modify**

### Legal and Ethical Considerations:
- Only deploy on networks you own or have explicit written permission to modify
- Respect network policies and terms of service
- Be aware of local laws regarding network monitoring and DNS modification
- Consider privacy implications for other network users

**By using this software, you acknowledge that you are solely responsible for ensuring compliance with all applicable laws, regulations, and network policies.**

---

## 🚀 Features

- **Real-time Dashboard**: Web-based interface for monitoring Pi-hole activity
- **Domain Categorization**: Automatic classification of domains (ads, social, malware, gambling, etc.)
- **Device Analytics**: Track and analyze activity by network device
- **Automated Updates**: Scheduled domain list updates with fallback sources
- **Comprehensive Logging**: Detailed activity tracking and retention management
- **Health Monitoring**: System health checks and automated maintenance
- **Blocking Analytics**: Detailed analysis of blocked content and categories

## 📋 Prerequisites

### 1. Setup WSL on Windows (Windows Users Only)

If you're running this on Windows, you'll need Windows Subsystem for Linux (WSL):

1. **Enable WSL**:
   ```powershell
   # Run as Administrator in PowerShell
   wsl --install
   ```

2. **Install Ubuntu** (recommended):
   ```powershell
   wsl --install -d Ubuntu
   ```

3. **Set up Ubuntu**:
   - Launch Ubuntu from Start Menu
   - Create username and password when prompted
   - Update system:
     ```bash
     sudo apt update && sudo apt upgrade -y
     ```

4. **Access Windows files from WSL**:
   - Windows C: drive is at `/mnt/c/`
   - Your user folder: `/mnt/c/Users/YourUsername/`

### 2. Install and Setup Pi-hole

#### Option A: Fresh Pi-hole Installation

1. **Install Pi-hole**:
   ```bash
   curl -sSL https://install.pi-hole.net | bash
   ```

2. **Follow the installation wizard**:
   - Select network interface
   - Choose upstream DNS provider (Cloudflare: 1.1.1.1 recommended)
   - Select blocklists (default is fine)
   - Install web admin interface (recommended)
   - Install web server (lighttpd recommended)
   - Enable logging (required for this monitoring system)

3. **Note the admin password** displayed at the end of installation

4. **Access Pi-hole Admin**:
   - Open browser: `http://your-pi-ip/admin`
   - Login with the admin password

#### Option B: Existing Pi-hole Setup

If you already have Pi-hole installed:

1. **Verify Pi-hole is running**:
   ```bash
   pihole status
   ```

2. **Ensure logging is enabled**:
   ```bash
   pihole logging on
   ```

3. **Check database location**:
   ```bash
   ls -la /etc/pihole/pihole-FTL.db
   ```

### 3. Configure Network Devices

1. **Set Pi-hole as DNS server** on your router or individual devices
2. **Router method** (recommended):
   - Access router admin panel
   - Set primary DNS to Pi-hole IP address
   - Set secondary DNS to 1.1.1.1 or 8.8.8.8
   - Restart router

3. **Individual device method**:
   - Windows: Network Settings → Change adapter options → Properties → IPv4 → DNS
   - Android: WiFi Settings → Advanced → Static IP → DNS1
   - iOS: WiFi Settings → Configure DNS → Manual

## 🛠️ Installation

### 1. Download and Run Setup Script

```bash
# Download the setup script
wget -O setup_pihole_monitor.sh [script-url]

# Make executable
chmod +x setup_pihole_monitor.sh

# Run setup
./setup_pihole_monitor.sh
```

### 2. Manual Installation (Alternative)

```bash
# Clone or create project directory
mkdir pihole-monitoring && cd pihole-monitoring

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install pandas nicegui requests python-dateutil schedule

# Copy the provided Python files to respective directories
# (domain_updater.py, log_parser.py, dashboard.py, etc.)
```

### 3. Configuration

1. **Update Pi-hole database path** (if different):
   ```bash
   # Edit config/config.py
   export PIHOLE_DB_PATH="/your/custom/path/pihole-FTL.db"
   ```

2. **Configure device mappings**:
   ```bash
   # Edit config/devices.json
   {
     "192.168.1.10": "John-Laptop",
     "192.168.1.11": "Sarah-Phone",
     "192.168.1.12": "Living-Room-TV"
   }
   ```

3. **Set dashboard port** (optional):
   ```bash
   export DASHBOARD_PORT=8080
   ```

## 🏃‍♂️ Usage

### 1. Start the Monitoring System

```bash
cd pihole-monitoring
source venv/bin/activate

# Start the dashboard
python dashboard.py
```

### 2. Start Background Monitoring (Optional)

```bash
# Start system monitoring and maintenance
python scripts/monitor.py
```

### 3. Access the Dashboard

Open your browser and navigate to:
```
http://localhost:8080
```
or
```
http://your-server-ip:8080
```

### 4. Manual Operations

#### Update Domain Lists
```bash
python domain_updater.py
```

#### Parse Recent Logs
```bash
python log_parser.py
```

#### Generate Reports
```bash
# In Python console
from log_parser import LogParser
parser = LogParser()
df = parser.parse_logs(days=7)  # Last 7 days
summary = parser.generate_summary(df)
print(summary)
```

## 📊 Dashboard Features

### Overview Tab
- Total queries and blocked percentage
- Most queried domains
- Device activity summary
- Real-time statistics

### Categories Tab
- Domain categorization breakdown
- Category-based filtering
- Blocked content analysis by type

### Devices Tab
- Per-device query statistics
- Device activity patterns
- Individual device filtering

### Blocked Content Tab
- Most blocked domains
- Blocking reasons and methods
- Category analysis of blocked content

### Timeline Tab
- Hourly query patterns
- Daily activity trends
- Peak usage identification

## 🔧 System Components

### Core Scripts

1. **`domain_updater.py`**
   - Downloads and categorizes domain lists
   - Supports multiple sources with fallbacks
   - Automatic retry logic and error handling

2. **`log_parser.py`**
   - Parses Pi-hole FTL database
   - Categorizes domains and maps devices
   - Generates comprehensive analytics

3. **`dashboard.py`**
   - Web-based monitoring interface
   - Real-time data visualization
   - Interactive filtering and analysis

4. **`monitor.py`**
   - Background system maintenance
   - Scheduled domain updates
   - Health monitoring and reporting
   - Log rotation and cleanup

### Automation Features

- **Daily domain list updates** at 2:00 AM
- **Log cleanup** at 3:00 AM (removes files older than 30 days)
- **Daily reports** generated at 11:55 PM
- **Hourly health checks** for system monitoring

## 🔍 Configuration Files

### `config/config.py`
Main configuration file containing:
- Database paths and connection settings
- Domain source URLs and categories
- Dashboard settings and ports
- Logging configuration
- Retention policies

### `config/devices.json`
Device mapping for friendly names:
```json
{
  "192.168.1.10": "Dad-Laptop",
  "192.168.1.11": "Kid-Tablet",
  "192.168.1.12": "Smart-TV"
}
```

## 📁 Directory Structure

```
pihole-monitoring/
├── config/
│   ├── config.py          # Main configuration
│   └── devices.json       # Device mappings
├── domains/
│   ├── ads_domains.txt    # Ad blocking domains
│   ├── social_domains.txt # Social media domains
│   └── ...               # Other category files
├── logs/
│   ├── application.log    # Main application log
│   ├── daily_report_*.json # Daily reports
│   └── health_*.json     # System health logs
├── scripts/
│   └── monitor.py        # Background monitoring
├── venv/                 # Python virtual environment
├── domain_updater.py     # Domain list updater
├── log_parser.py         # Log parsing engine
└── dashboard.py          # Web dashboard
```

## 🛠️ Troubleshooting

### Common Issues

1. **"Permission denied" accessing Pi-hole database**:
   ```bash
   sudo chmod 644 /etc/pihole/pihole-FTL.db
   sudo chown pihole:pihole /etc/pihole/pihole-FTL.db
   ```

2. **Dashboard not accessible**:
   - Check if port 8080 is open: `sudo ufw allow 8080`
   - Verify firewall settings
   - Try accessing via `http://127.0.0.1:8080`

3. **No data in dashboard**:
   - Verify Pi-hole logging is enabled: `pihole logging on`
   - Check database path in config
   - Ensure Pi-hole has been running and processing queries

4. **Domain updates failing**:
   - Check internet connectivity
   - Verify domain source URLs are accessible
   - Review logs in `logs/application.log`

### Log Files

- **Application logs**: `logs/application.log`
- **System health**: `logs/health_YYYYMMDD.json`
- **Daily reports**: `logs/daily_report_YYYYMMDD.json`

## 🚀 Potential Improvements

### Performance & Scalability
- **Database optimization**: Add indexes and query optimization for faster data retrieval
- **Caching layer**: Implement Redis/Memcached for frequently accessed data
- **Asynchronous processing**: Use asyncio for non-blocking database operations
- **Data compression**: Compress old logs and reports to save storage space

### Visualization & UI
- **Interactive charts**: Replace static tables with dynamic Plotly/Chart.js visualizations
- **Real-time updates**: WebSocket implementation for live dashboard updates
- **Mobile responsive design**: Optimize dashboard for mobile and tablet viewing
- **Dark mode toggle**: Add theme switching capability for better user experience
- **Export functionality**: Add CSV/PDF export options for reports and data

### Analytics & Intelligence
- **Machine learning anomaly detection**: Identify unusual network patterns or security threats
- **Predictive analytics**: Forecast network usage patterns and potential issues
- **Geolocation analysis**: Map blocked domains to geographic sources
- **Threat intelligence integration**: Connect with external threat feeds for enhanced security
- **Custom alerting system**: Email/SMS notifications for security events or system issues

### Security & Monitoring
- **Authentication system**: Add user login and role-based access control
- **API rate limiting**: Implement request throttling for external API calls
- **Encrypted connections**: HTTPS support with SSL/TLS certificates
- **Audit logging**: Track user actions and system changes
- **Backup automation**: Scheduled backups of configuration and historical data

### Integration & Extensibility
- **Multi Pi-hole support**: Monitor multiple Pi-hole instances from single dashboard
- **Home automation integration**: Connect with Home Assistant, OpenHAB, etc.
- **Cloud synchronization**: Sync configurations and reports to cloud storage
- **Webhook notifications**: Send alerts to Discord, Slack, or other services
- **Plugin architecture**: Modular system for custom extensions and integrations

### Data Management
- **Time-series database**: Migrate to InfluxDB for better time-series data handling
- **Data archiving**: Automatic archival of old data to cold storage
- **Configuration management**: Version control for configuration changes
- **Multi-tenant support**: Support for multiple networks or locations
- **Advanced filtering**: Complex query builder for detailed data analysis

---

## 📝 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## 📞 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review log files for error messages
3. Open an issue on the project repository
4. Consult Pi-hole documentation for Pi-hole specific issues
