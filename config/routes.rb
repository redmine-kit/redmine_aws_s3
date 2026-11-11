# frozen_string_literal: true

post 's3_uploads/presign', to: 's3_uploads#presign'
post 's3_uploads/complete', to: 's3_uploads#complete'
post 's3_uploads/avatar/presign', to: 's3_avatar_uploads#presign'
post 's3_uploads/avatar/check', to: 's3_avatar_uploads#check'

get 'admin/aws/s3', to: 'aws_s3_admin#show', as: 'aws_s3_admin'
patch 'admin/aws/s3', to: 'aws_s3_admin#update'
post 'admin/aws/s3/read_write', to: 'aws_s3_admin#read_write', as: 'aws_s3_admin_read_write'
post 'admin/aws/s3/delivery', to: 'aws_s3_admin#delivery', as: 'aws_s3_admin_delivery'
post 'admin/aws/s3/reconcile', to: 'aws_s3_admin#reconcile', as: 'aws_s3_admin_reconcile'
