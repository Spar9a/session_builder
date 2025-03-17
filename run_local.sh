#!/bin/bash

var mount_dir=./docker_mount/docker_mvp_data

# Create data directories
mkdir -p $mount_dir/raw-data $mount_dir/processed-data $mount_dir/deltalake-table

# Check if continuous mode is requested
if [ "$1" == "--continuous" ]; then
    echo "Running in continuous mode"
    CONTINUOUS_MODE=True docker-compose -f docker-compose.mvp_solution.yml up --build
else
    # Run the Docker containers in default mode
    docker-compose -f docker-compose.mvp_solution.yml up --build
fi