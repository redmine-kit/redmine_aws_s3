# frozen_string_literal: true

# The shared entry of the Serverless administration menu (every Redmine
# Serverless plugin draws it; the first one matches).
get 'admin/serverless', to: 'serverless_admin#index'

post 's3_uploads/presign', to: 's3_uploads#presign'
post 's3_uploads/complete', to: 's3_uploads#complete'

get 'admin/serverless/s3', to: 'serverless_s3_admin#show', as: 'serverless_s3_admin'
patch 'admin/serverless/s3', to: 'serverless_s3_admin#update'
post 'admin/serverless/s3/read_write', to: 'serverless_s3_admin#read_write', as: 'serverless_s3_admin_read_write'
post 'admin/serverless/s3/delivery', to: 'serverless_s3_admin#delivery', as: 'serverless_s3_admin_delivery'
post 'admin/serverless/s3/reconcile', to: 'serverless_s3_admin#reconcile', as: 'serverless_s3_admin_reconcile'
