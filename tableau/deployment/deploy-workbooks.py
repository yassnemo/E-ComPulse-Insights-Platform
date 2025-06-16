#!/usr/bin/env python3
"""
Tableau Workbook Deployment Script

This script automates the deployment of Tableau workbooks to Tableau Server,
including data source configuration, permission setup, and refresh scheduling.
"""

import os
import sys
import json
import argparse
import logging
from typing import List, Dict, Optional
from pathlib import Path

import tableauserverclient as TSC
import requests
from requests.auth import HTTPBasicAuth


class TableauDeployer:
    """Handles deployment of Tableau workbooks and configuration"""
    
    def __init__(self, server_url: str, username: str, password: str, site_id: str = ""):
        """
        Initialize Tableau Server connection
        
        Args:
            server_url: Tableau Server URL
            username: Username for authentication
            password: Password for authentication  
            site_id: Site ID (empty for default site)
        """
        self.server_url = server_url
        self.username = username
        self.password = password
        self.site_id = site_id
        
        # Initialize Tableau Server Client
        self.server = TSC.Server(server_url)
        self.auth = TSC.TableauAuth(username, password, site_id)
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
    
    def connect(self) -> bool:
        """
        Connect to Tableau Server
        
        Returns:
            bool: True if connection successful, False otherwise
        """
        try:
            self.server.auth.sign_in(self.auth)
            self.logger.info(f"Successfully connected to Tableau Server: {self.server_url}")
            return True
        except Exception as e:
            self.logger.error(f"Failed to connect to Tableau Server: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from Tableau Server"""
        try:
            self.server.auth.sign_out()
            self.logger.info("Disconnected from Tableau Server")
        except Exception as e:
            self.logger.error(f"Error disconnecting: {e}")
    
    def create_project(self, project_name: str, description: str = "") -> Optional[str]:
        """
        Create a new project on Tableau Server
        
        Args:
            project_name: Name of the project
            description: Project description
            
        Returns:
            str: Project ID if successful, None otherwise
        """
        try:
            # Check if project already exists
            projects, _ = self.server.projects.get()
            for project in projects:
                if project.name == project_name:
                    self.logger.info(f"Project '{project_name}' already exists")
                    return project.id
            
            # Create new project
            new_project = TSC.ProjectItem(
                name=project_name,
                description=description
            )
            new_project = self.server.projects.create(new_project)
            self.logger.info(f"Created project '{project_name}' with ID: {new_project.id}")
            return new_project.id
            
        except Exception as e:
            self.logger.error(f"Failed to create project '{project_name}': {e}")
            return None
    
    def publish_workbook(self, workbook_path: str, project_name: str, 
                        overwrite: bool = True) -> Optional[str]:
        """
        Publish a workbook to Tableau Server
        
        Args:
            workbook_path: Path to the workbook file
            project_name: Target project name
            overwrite: Whether to overwrite existing workbook
            
        Returns:
            str: Workbook ID if successful, None otherwise
        """
        try:
            # Find the target project
            projects, _ = self.server.projects.get()
            target_project = None
            for project in projects:
                if project.name == project_name:
                    target_project = project
                    break
            
            if not target_project:
                self.logger.error(f"Project '{project_name}' not found")
                return None
            
            # Create workbook item
            workbook_name = Path(workbook_path).stem
            new_workbook = TSC.WorkbookItem(
                name=workbook_name,
                project_id=target_project.id
            )
            
            # Publish workbook
            publish_mode = TSC.Server.PublishMode.Overwrite if overwrite else TSC.Server.PublishMode.CreateNew
            new_workbook = self.server.workbooks.publish(
                new_workbook, 
                workbook_path, 
                publish_mode
            )
            
            self.logger.info(f"Published workbook '{workbook_name}' with ID: {new_workbook.id}")
            return new_workbook.id
            
        except Exception as e:
            self.logger.error(f"Failed to publish workbook '{workbook_path}': {e}")
            return None
    
    def publish_data_source(self, datasource_path: str, project_name: str,
                           overwrite: bool = True) -> Optional[str]:
        """
        Publish a data source to Tableau Server
        
        Args:
            datasource_path: Path to the data source file
            project_name: Target project name
            overwrite: Whether to overwrite existing data source
            
        Returns:
            str: Data source ID if successful, None otherwise
        """
        try:
            # Find the target project
            projects, _ = self.server.projects.get()
            target_project = None
            for project in projects:
                if project.name == project_name:
                    target_project = project
                    break
            
            if not target_project:
                self.logger.error(f"Project '{project_name}' not found")
                return None
            
            # Create data source item
            datasource_name = Path(datasource_path).stem
            new_datasource = TSC.DatasourceItem(
                name=datasource_name,
                project_id=target_project.id
            )
            
            # Publish data source
            publish_mode = TSC.Server.PublishMode.Overwrite if overwrite else TSC.Server.PublishMode.CreateNew
            new_datasource = self.server.datasources.publish(
                new_datasource,
                datasource_path,
                publish_mode
            )
            
            self.logger.info(f"Published data source '{datasource_name}' with ID: {new_datasource.id}")
            return new_datasource.id
            
        except Exception as e:
            self.logger.error(f"Failed to publish data source '{datasource_path}': {e}")
            return None
    
    def set_workbook_permissions(self, workbook_id: str, permissions: Dict) -> bool:
        """
        Set permissions for a workbook
        
        Args:
            workbook_id: Workbook ID
            permissions: Permission configuration
            
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Get workbook
            workbook = self.server.workbooks.get_by_id(workbook_id)
            
            # Clear existing permissions
            self.server.workbooks.delete_permissions(workbook)
            
            # Set new permissions
            for user_or_group, perms in permissions.items():
                if perms.get('type') == 'user':
                    grantee = TSC.UserItem()
                    grantee.name = user_or_group
                elif perms.get('type') == 'group':
                    grantee = TSC.GroupItem()
                    grantee.name = user_or_group
                else:
                    continue
                
                # Create permission rules
                permission_rules = []
                for capability, mode in perms.get('capabilities', {}).items():
                    if mode == 'allow':
                        permission_rules.append(TSC.PermissionsRule(
                            grantee=grantee,
                            capabilities={capability: TSC.PermissionsRule.Mode.Allow}
                        ))
                    elif mode == 'deny':
                        permission_rules.append(TSC.PermissionsRule(
                            grantee=grantee,
                            capabilities={capability: TSC.PermissionsRule.Mode.Deny}
                        ))
                
                # Apply permissions
                for rule in permission_rules:
                    self.server.workbooks.add_permissions(workbook, [rule])
            
            self.logger.info(f"Set permissions for workbook ID: {workbook_id}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to set permissions for workbook '{workbook_id}': {e}")
            return False
    
    def schedule_refresh(self, workbook_id: str, schedule_name: str,
                        frequency: str, time: str) -> bool:
        """
        Schedule automatic refresh for a workbook
        
        Args:
            workbook_id: Workbook ID
            schedule_name: Name for the schedule
            frequency: Frequency (Daily, Weekly, Monthly)
            time: Time to run (HH:MM format)
            
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Get existing schedules
            schedules, _ = self.server.schedules.get()
            target_schedule = None
            
            for schedule in schedules:
                if schedule.name == schedule_name:
                    target_schedule = schedule
                    break
            
            # Create schedule if it doesn't exist
            if not target_schedule:
                new_schedule = TSC.ScheduleItem(
                    name=schedule_name,
                    priority=50,
                    schedule_type=TSC.ScheduleItem.Type.Extract,
                    execution_order=TSC.ScheduleItem.ExecutionOrder.Parallel
                )
                
                # Set frequency
                if frequency.lower() == 'daily':
                    interval = TSC.DailyInterval(start_time=time)
                elif frequency.lower() == 'weekly':
                    interval = TSC.WeeklyInterval(start_time=time)
                elif frequency.lower() == 'monthly':
                    interval = TSC.MonthlyInterval(start_time=time)
                else:
                    self.logger.error(f"Unsupported frequency: {frequency}")
                    return False
                
                new_schedule.interval_item = interval
                target_schedule = self.server.schedules.create(new_schedule)
                self.logger.info(f"Created schedule '{schedule_name}'")
            
            # Add workbook to schedule
            workbook = self.server.workbooks.get_by_id(workbook_id)
            self.server.schedules.add_to_schedule(target_schedule, workbook)
            
            self.logger.info(f"Added workbook to schedule '{schedule_name}'")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to schedule refresh for workbook '{workbook_id}': {e}")
            return False
    
    def deploy_environment(self, config_file: str) -> bool:
        """
        Deploy complete environment from configuration file
        
        Args:
            config_file: Path to configuration file
            
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            
            # Create projects
            for project_config in config.get('projects', []):
                project_id = self.create_project(
                    project_config['name'],
                    project_config.get('description', '')
                )
                if not project_id:
                    return False
            
            # Publish data sources
            for ds_config in config.get('data_sources', []):
                ds_id = self.publish_data_source(
                    ds_config['file_path'],
                    ds_config['project'],
                    ds_config.get('overwrite', True)
                )
                if not ds_id:
                    return False
            
            # Publish workbooks
            for wb_config in config.get('workbooks', []):
                wb_id = self.publish_workbook(
                    wb_config['file_path'],
                    wb_config['project'],
                    wb_config.get('overwrite', True)
                )
                if not wb_id:
                    return False
                
                # Set permissions
                if 'permissions' in wb_config:
                    self.set_workbook_permissions(wb_id, wb_config['permissions'])
                
                # Schedule refresh
                if 'schedule' in wb_config:
                    schedule_config = wb_config['schedule']
                    self.schedule_refresh(
                        wb_id,
                        schedule_config['name'],
                        schedule_config['frequency'],
                        schedule_config['time']
                    )
            
            self.logger.info("Environment deployment completed successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to deploy environment: {e}")
            return False


def main():
    """Main function to handle command line arguments and execute deployment"""
    parser = argparse.ArgumentParser(description='Deploy Tableau workbooks to Tableau Server')
    parser.add_argument('--config', required=True, help='Configuration file path')
    parser.add_argument('--environment', required=True, help='Environment (dev/staging/production)')
    parser.add_argument('--workbook', help='Specific workbook to deploy (optional)')
    parser.add_argument('--server-url', help='Tableau Server URL')
    parser.add_argument('--username', help='Username')
    parser.add_argument('--password', help='Password')
    parser.add_argument('--site-id', default='', help='Site ID')
    
    args = parser.parse_args()
    
    # Load configuration
    try:
        with open(args.config, 'r') as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error loading configuration: {e}")
        sys.exit(1)
    
    # Get environment-specific settings
    env_config = config.get('environments', {}).get(args.environment)
    if not env_config:
        print(f"Environment '{args.environment}' not found in configuration")
        sys.exit(1)
    
    # Get connection details
    server_url = args.server_url or env_config.get('server_url')
    username = args.username or env_config.get('username')
    password = args.password or env_config.get('password')
    site_id = args.site_id or env_config.get('site_id', '')
    
    if not all([server_url, username, password]):
        print("Missing required connection details")
        sys.exit(1)
    
    # Initialize deployer
    deployer = TableauDeployer(server_url, username, password, site_id)
    
    # Connect to server
    if not deployer.connect():
        sys.exit(1)
    
    try:
        # Deploy specific workbook or entire environment
        if args.workbook:
            # Find workbook configuration
            workbook_config = None
            for wb_config in config.get('workbooks', []):
                if wb_config['name'] == args.workbook:
                    workbook_config = wb_config
                    break
            
            if not workbook_config:
                print(f"Workbook '{args.workbook}' not found in configuration")
                sys.exit(1)
            
            # Deploy single workbook
            wb_id = deployer.publish_workbook(
                workbook_config['file_path'],
                workbook_config['project'],
                workbook_config.get('overwrite', True)
            )
            
            if wb_id and 'permissions' in workbook_config:
                deployer.set_workbook_permissions(wb_id, workbook_config['permissions'])
                
            if wb_id and 'schedule' in workbook_config:
                schedule_config = workbook_config['schedule']
                deployer.schedule_refresh(
                    wb_id,
                    schedule_config['name'],
                    schedule_config['frequency'],
                    schedule_config['time']
                )
        else:
            # Deploy entire environment
            if not deployer.deploy_environment(args.config):
                sys.exit(1)
    
    finally:
        deployer.disconnect()


if __name__ == '__main__':
    main()
