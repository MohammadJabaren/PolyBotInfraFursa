output "control_plane_ip" {
  value = module.k8s-cluster.control_plane_ip
}
output "dynamodb_prediction_table_name" {
  value = module.k8s-cluster.dynamodb_prediction_table_name
}

output "dynamodb_detection_table_name" {
  value = module.k8s-cluster.dynamodb_detection_table_name
}

output "dynamodb_detection_label_score_index" {
  value = module.k8s-cluster.dynamodb_detection_label_score_index
}

output "dynamodb_detection_score_partition_index" {
  value = module.k8s-cluster.dynamodb_detection_score_partition_index
}

output "s3_bucket_name" {
  value = module.k8s-cluster.s3_bucket_name
}

output "sqs_queue_name" {
  value = module.k8s-cluster.sqs_queue_name
}

output "sqs_queue_url" {
  value = module.k8s-cluster.sqs_queue_url
}
