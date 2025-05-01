module Api
  module V1
    class BlobsController < ApiController
      def show
        blob = ActiveStorage::Blob.find_signed(params[:signed_id])

        if blob.image?
          # 对于图片，可以直接显示或提供特定尺寸的变体
          redirect_to rails_blob_url(blob)
        else
          # 对于其他文件类型，提供下载选项
          redirect_to rails_blob_url(blob, disposition: "attachment")
        end
      end
    end
  end
end
