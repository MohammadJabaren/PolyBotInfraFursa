output "control_plane_ip" {
  value = aws_instance.control_panel.public_ip
  description = "Public IP of the control plane EC2 instance"
}
output "dynamodb_prediction_table_name" {
  value = aws_dynamodb_table.prediction_objects.name
}

output "dynamodb_detection_table_name" {
  value = aws_dynamodb_table.detection_objects.name
}

output "dynamodb_detection_label_score_index" {
  value = "LabelScoreIndex"
}

output "dynamodb_detection_score_partition_index" {
  value = "score_partition-score-index"
}
output "s3_bucket_name" {
  value = aws_s3_bucket.s3.bucket
}
output "sqs_queue_name" {
  value = aws_sqs_queue.sqs.name
}

output "sqs_queue_url" {
  value = aws_sqs_queue.sqs.url
}

