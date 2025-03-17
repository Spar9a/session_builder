
module "storage" {
    source = "./modules/storage"
    aws_region = var.aws_region
    data_lake_bucket_name = local.data_lake_bucket_name
    raw_data_folder = var.raw_data_data_folder
    processed_data_folder = var.processed_data_folder_name
    build_storage_bucket_name= local.build_bucket_name
    deltalake_folder = var.deltalake_folder_name
    tags = var.tags
}

module "networking" {
    source = "./modules/networking"
    
    project_name        = var.project_name
    resources_name_prefix = local.name_prefix
    aws_region          = var.aws_region
    environment         = var.environment
    vpc_cidr            = var.vpc_cidr
    private_subnet_cidrs = var.private_subnet_cidrs
    tags                = local.tags
}

module "session_builder" {
    source = "./modules/session_builder"

    environment         = var.environment
    project_name = var.project_name
    resources_name_prefix = local.name_prefix
    aws_region = var.aws_region
    data_lake_bucket_arn = module.storage.data_lake_bucket_arn
    data_lake_bucket_name = module.storage.data_lake_bucket_name
    raw_data_folder_name = var.raw_data_data_folder
    deltalake_folder_name = var.deltalake_folder_name
    processed_data_folder_name = var.processed_data_folder_name
    build_storage_bucket_name= module.storage.build_storage_bucket_name
    vpc_cidr = module.networking.vpc_cidr
    vpc_id = module.networking.vpc_id

    worker_count = var.worker_count
    master_instance_type = var.master_instance_type
    worker_instance_type = var.worker_instance_type
    private_subnet_id = module.networking.private_subnet_id
    spark_ami_id = var.spark_ami_id
    private_subnet_ids = module.networking.private_subnet_ids

    tags = local.tags
}

module "monitoring" {
    source = "./modules/monitoring"

    environment = var.environment
    project_name = var.project_name
    resources_name_prefix = local.name_prefix

    session_builder_workflow_arn = module.session_builder.session_builder_workflow_arn
    aws_region                   = var.aws_region
    processing_schedule          = var.schedule_expression
}

module "fake_data_generator" {
    source = "./modules/fake_data_generator"
    resources_name_prefix = local.name_prefix
    data_lake_bucket_name     = module.storage.build_storage_bucket_name
    raw_data_folder           = var.raw_data_data_folder
}