require 'json'

module Chemistry
  class PagesController < Chemistry::ApplicationController
    include Chemistry::Concerns::Searchable

    # specially-named page routes make it easier to skip authentication
    load_and_authorize_resource except: [:published, :latest, :home, :bundle]

    # HTML routes
    #
    # public front page
    #
    def home
      if @page = Chemistry::Page.home.first
        render template: "chemistry/pages/published"
      else
        render template: "chemistry/welcome", layout: "chemistry/application"
      end
    end

    def welcome
      render template: "chemistry/welcome", layout: "chemistry/application"
    end

    # Editing front page
    #
    def editor
      render
    end

    # Any page, in its published form.
    #
    def published
      @path = params[:path] || ''
      @path.sub /\/$/, ''
      @path.sub /^\//, ''
      if @page = Chemistry::Page.published.with_path(@path.strip).first
        render
      else
        page_not_found
      end
    end


    # API routes
    #
    # Support the editing UI and a few public functions like list pagination.
    #
    # `site` is an init package for the editing UI.
    #
    # Serialized collections do not include associates: the object must be fetched singly
    # to get eg. page sections or template placeholders.
    #
    # TODO soon we will need a real Site object but for now this shortcut.
    # API will be preserved, more or less.
    #
    def site
      render json: {
        pages: PageSerializer.new(Page.all).serializable_hash,
        templates: TemplateSerializer.new(Template.all).serializable_hash,
        section_types: SectionTypeSerializer.new(SectionType.all).serializable_hash,
        locales: Chemistry.locale_urls
      }
    end

    # `bundle` is a package of all published pages suitable for presentation in eg. an app.
    # etag / cache metadata v important because though the package not expensive to build,
    # it is bulky and likely to be delivered over mobile data.
    # TODO soon to be another view of the Site object.
    #
    def bundle
      if latest_page = Page.published.latest.limit(1).first
        if stale?(etag: latest_page, last_modified: latest_page.published_at, public: true)
          @pages = Page.published
          return_pages_with_everything
        end
      end
    end

    def index
      return_pages
    end

    def show
      return_page if stale?(etag: @page, last_modified: @page.published_at, public: true)
    end

    # `latest` returns a list useful for populating sidebars and menus with 'latest update' type blocks
    # optional `parent` param contains a path string, scopes the list to children of the page at that path.
    #
    def latest
      limit = params[:limit].presence || 1
      @pages = Page.published.latest.limit(limit)

      Rails.logger.warn "LATEST under path #{params[:parent]} with limit #{limit}"

      if params[:parent] and parent_page = Page.where(path: params[:parent]).first
        @pages = @pages.with_parent(parent_page)
      end
      render partial: "chemistry/pages/excerpt", collection: @pages
    end

    # `children` returns paginated lists of published pages under the given page path.
    #
    def children
      limit = params[:limit].presence || 20
      parent_page = Page.where(path: params[:parent]).first
      @pages = parent_page.child_pages.published.order(published_at: :desc).limit(limit)

      Rails.logger.warn "CHILDREN under path #{params[:parent]} with limit #{limit}"

      render partial: "chemistry/pages/excerpt", collection: @pages
    end

    def create
      if @page.update_attributes(create_page_params)
        return_page
      else
        return_errors
      end
    end

    def update
      if @page.update_attributes(update_page_params)
        @page.touch
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
      render json: PageSerializer.new(@pages).serialized_json
    end

    def return_pages_with_everything
      render json: PublicPageSerializer.new(@pages, include: [:sections, :socials, :image, :video]).serialized_json
    end

    def return_page
      render json: PageSerializer.new(@page).serialized_json
    end

    def return_errors
      render json: { errors: @page.errors.to_a }, status: :unprocessable_entity
    end


    ## Error pages

    def page_not_found
      if @page = Page.published.with_path("/404").first
        render
      else
        render template: "chemistry/pages/not_found"
      end
    end



    protected
  
    def create_page_params
      params.require(:page).permit(
        :slug,
        :template_id,
        :parent_id,
        :content,
        :keywords,
        :external_url,
        :title
      )
    end

    def update_page_params
      params.require(:page).permit(
        :id,
        :slug,
        :home,
        :template_id,
        :parent_id,
        :content,
        :external_url,
        :document_id,
        :prefix,
        :title,
        :summary,
        :excerpt,
        :rendered_html,
        :image_id,
        :video_id,
        :nav,               # takes part in navigation?
        :nav_name,          # with this name
        :nav_position,      # in this position
        :keywords,
        :date,
        :to_date,
        socials_data: [    # + nested socials data
          :position,
          :platform,
          :name,
          :reference,
          :url
        ],
        sections_data: [    # + nested section data
          :id,
          :section_type_id,
          :position,
          :prefix,
          :title,
          :primary_html,
          :secondary_html,
          :background_html,
          :deleted_at
        ]
      )
    end


    ## Searchable configuration
    #
    def search_fields
      ['title^10', 'terms^5', 'content']
    end

    def search_highlights
      {tag: "<strong>"}
    end

    def search_default_sort
      "title"
    end

  end
end