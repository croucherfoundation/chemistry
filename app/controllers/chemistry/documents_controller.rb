module Chemistry
  class DocumentsController < ApplicationController
    load_and_authorize_resource

    def index
      return_documents
    end
  
    def show
      return_document
    end
  
    def create
      if @document.update_attributes(document_params)
        return_document
      else
        return_errors
      end
    end

    def update
      if @document.update_attributes(document_params)
        return_document
      else
        return_errors
      end
    end
    
    def destroy
      @document.destroy
      head :no_content
    end


    ## Standard responses

    def return_documents
      render json: DocumentSerializer.new(@documents)
    end

    def return_document
      render json: DocumentSerializer.new(@document)
    end

    def return_errors
      render json: { errors: @document.errors.to_a }, status: :unprocessable_entity
    end


    protected

    def document_params
      params.permit(
        :file,
        :file_name,
        :page_id,
        :caption,
        :remote_url
      )
    end

  end
end