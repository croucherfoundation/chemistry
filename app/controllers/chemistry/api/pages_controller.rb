require 'json'

module Chemistry::Api
  class PagesController < Chemistry::Api::ApiController
    include Chemistry::Concerns::Searchable
    load_resource class: Chemistry::Page, except: [:index]

    ## API routes
    # Support the editing UI and a few public functions like list pagination.
    #
    def index
      return_pages
    end

    def show
      return_page if stale?(etag: @page, last_modified: @page.published_at, public: true)
    end

    def branch
      # return all the pages that are children of a given stem,
      # and within a given page_collection
    end

    def create
      if @page.update_attributes(page_params.merge(user_id: current_user.id))
        return_page
      else
        return_errors
      end
    end

    def update
      if @page.update_attributes(page_params)
        return_page
      else
        return_errors
      end
    end

    def publish
      if @page.publish!(publish_params)
        return_page
      else
        return_errors
      end
    end

    def destroy
      @page.destroy
      head :no_content
    end


    ## Standard API responses

    def return_pages
      render json: Chemistry::TreePageSerializer.new(@pages).serialized_json
    end

    def return_pages_with_everything
      render json: Chemistry::PublicPageSerializer.new(@pages, include: [:socials, :image, :video]).serialized_json
    end

    def return_page
      render json: Chemistry::PageSerializer.new(@page).serialized_json
    end

    def return_errors
      render json: { errors: @page.errors.to_a }, status: :unprocessable_entity
    end


    ## Error pages

    def page_not_found
      head :not_found
    end


    protected
  
    ## Permitted parameters
    #
    # New-page link can set basic properties
    #
    def new_page_params
      params.permit(
        :slug,
        :private,
        :title
      )
    end
  
    def page_params
      params.require(:page).permit(
        :parent_id,
        :slug,
        :private,
        :style,
        :title,             # authoring page parts
        :content,           #
        :masthead,          #
        :excerpt,
        :nav,               # takes part in navigation?
        :nav_name,          # with this name
        :nav_position,      # in this position
        :terms
      )
    end

    def publish_params
      params.require(:page).permit(
        :published_title,
        :published_html,
        :published_excerpt
      )
    end

    ## Searchable configuration
    #
    def search_class
      Chemistry::Page
    end

    def search_fields
      ['title^10', 'terms^5', 'content']
    end

    def search_highlights
      {tag: "<strong>"}
    end

    def search_default_sort
      "title"
    end

    def paginated?
      false
    end

  end
end