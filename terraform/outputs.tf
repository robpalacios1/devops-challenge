output "site_bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "logs_bucket_name" {
  value = aws_s3_bucket.logs.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  value = "https://${aws_cloudfront_distribution.site.domain_name}"
}