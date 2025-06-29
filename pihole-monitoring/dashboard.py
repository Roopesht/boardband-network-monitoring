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
