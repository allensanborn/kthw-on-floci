# Addresses before bootstrap/ stopped using for_each (2026-10-16); keeps applied buckets in place.
moved {
  from = aws_s3_bucket.this["state"]
  to   = aws_s3_bucket.state
}

moved {
  from = aws_s3_bucket.this["logs"]
  to   = aws_s3_bucket.logs
}

moved {
  from = aws_s3_bucket_public_access_block.this["state"]
  to   = aws_s3_bucket_public_access_block.state
}

moved {
  from = aws_s3_bucket_public_access_block.this["logs"]
  to   = aws_s3_bucket_public_access_block.logs
}

moved {
  from = aws_s3_bucket_ownership_controls.this["state"]
  to   = aws_s3_bucket_ownership_controls.state
}

moved {
  from = aws_s3_bucket_ownership_controls.this["logs"]
  to   = aws_s3_bucket_ownership_controls.logs
}

moved {
  from = aws_s3_bucket_versioning.this["state"]
  to   = aws_s3_bucket_versioning.state
}

moved {
  from = aws_s3_bucket_versioning.this["logs"]
  to   = aws_s3_bucket_versioning.logs
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.this["state"]
  to   = aws_s3_bucket_lifecycle_configuration.state
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.this["logs"]
  to   = aws_s3_bucket_lifecycle_configuration.logs
}

moved {
  from = aws_s3_bucket_policy.this["state"]
  to   = aws_s3_bucket_policy.state
}

moved {
  from = aws_s3_bucket_policy.this["logs"]
  to   = aws_s3_bucket_policy.logs
}
