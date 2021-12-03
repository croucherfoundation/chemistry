module Chemistry
  class PagesController < Chemistry::ApplicationController
    include Chemistry::Concerns::Searchable

    skip_before_action :authenticate_user!, only: [:home, :published, :latest, :search, :children, :siblings, :similar, :listed, :controls], raise: false
    load_and_authorize_resource class: Chemistry::Page, except: [:home, :published, :latest, :children, :siblings, :controls, :search]
    before_action :get_view, only: [:edit]


    ## Published pages for public users
    #
    def home
      @page = Chemistry::Page.home.first
      if @page && @page.published?
        if stale?(etag: @page, last_modified: @page.published_at)
          render template: "chemistry/pages/published", layout: chemistry_layout
        end
      else
        render template: "chemistry/welcome", layout: "chemistry/application"
      end
    end

    def published
      @path = (params[:path] || '').sub(/\/$/, '').sub(/^\//, '').strip
      @page = Chemistry::Page.published_with_path(@path)
      if @page
        if @page.passworded?
          if authenticate_with_http_basic { |u, p| p == @page.password }
            render layout: chemistry_layout
          else
            request_http_basic_authentication
          end
        elsif @page && (@page.public? || user_signed_in?)
          render layout: chemistry_layout
        end
      else
        page_not_found
      end
    end

    def search
      if params[:pp] == 'all'
        @params = search_params
      else
        page = params[:p] || 1
        per_page = params[:pp] || 20
        @params = search_params.to_h.merge(p: page, pp: per_page)
      end
      @q = helpers.strip_tags(@params[:q])
      @sort = params[:sort]
      @page_collection = Chemistry::PageCollection.find_by(slug: @params[:page_collection]) if @params[:page_collection].present?
      @pages = Chemistry::Page.search_and_aggregate(@params)
      render layout: chemistry_search_layout
    end


    # Welcome to empty site
    #
    def welcome
      render template: "chemistry/welcome", layout: "chemistry/application"
    end


    # Page-tree management for admin users
    # All our basic page-crud happens within this view, then we jump to the editor for content creation.
    #
    def index
      @page_tree = Chemistry::Page.page_tree
      render layout: chemistry_admin_layout
    end

    # New returns a tiny inline form that will create an empty page and forward to edit
    #
    def new
      @page = Chemistry::Page.new(page_params)
      @page.page_collection_id = params[:page_collection_id]
      render layout: no_layout_if_pjax
    end

    def create
      @page = Chemistry::Page.new(page_params.merge(user_id: user_signed_in? && current_user.id))
      if @page.save
        redirect_to editor_page_url(@page)
      else
        render action: "new", layout: false
      end
    end

    def update
      if @page.update(page_params)
        render :partial => "branch", locals: {branch: Chemistry::Page.page_tree(@page)}
      else
        render action: "edit", layout: false
      end
    end

    def branch
      render :partial => "branch", locals: {branch: Chemistry::Page.page_tree(@page)}
    end

    # `edit` shows page configuration forms based on a `view` parameter.
    # `editor` shows the SPA editor and the rest of the edit and save process goes through the API,
    #
    def edit
      render layout: no_layout_if_pjax
    end

    def editor
      render layout: chemistry_editing_layout
    end

    def destroy
      @page.destroy
      head :no_content
    end

    # Page fragments
    #
    # `latest` returns a list useful for populating sidebars and menus with 'latest update' type blocks
    # optional `parent` param contains a path string, scopes the list to children of the page at that path.
    #
    def latest
      limit = params[:limit].presence || 1
      @pages = Page.published.latest.limit(limit)
      if params[:parent] and @page = Chemistry::Page.where(path: params[:parent]).first
        @pages = @pages.with_parent(@page)
      end
      if @pages && @pages.any?
        render template: "chemistry/pages/toc", layout: false
      else
        head :no_content
      end
    end

    # `children` returns a toc list of published pages under the given page id.
    #
    def children
      if params[:page_id].present?
        @page = Chemistry::Page.find(params[:page_id])
        @pages = Chemistry::Page.search(where: {parent_id: params[:page_id]}, load: false);
      end
      if @pages && @pages.any?
        render template: "chemistry/pages/toc", layout: false
      else
        head :no_content
      end
    end

    def siblings
      if params[:page_id].present?
        @page = Chemistry::Page.find(params[:page_id])
        Rails.logger.warn("👨‍👨‍👧 siblings -> #{@page.parent_id}")  # TODO how do we do this again?
        if parent_id = @page.parent_id
          @pages = Chemistry::Page.search(where: {parent_id: parent_id}, load: false);
        end
      end
      if @pages && @pages.any?
        render template: "chemistry/pages/toc", layout: false
      else
        head :no_content
      end
    end

    # `similar` returns a toc list of published pages under the given page id.
    #
    def similar
      @page = Chemistry::Page.find(params[:page_id])
      @pages = @page.similar_pages
      if @pages && @pages.any?
        render template: "chemistry/pages/toc", layout: false
      else
        head :no_content
      end
    end

    def listed
      if params[:page_ids].present?
        page_ids = params[:page_ids].split(',').map(&:to_i).compact.uniq
        @pages = Chemistry::Page.search(where: {id: page_ids}, load: false);
      end
      if @pages && @pages.any?
        render template: "chemistry/pages/toc", layout: false
      else
        head :no_content
      end
    end

    # Control block added to (cacheable) public page if user is signed in.
    #
    def controls
      if params[:id].present? && can?(:edit, Chemistry::Page)
        @page = Chemistry::Page.find_by(slug: params[:id])
        render layout: false
      else
        head :no_content
      end
    end


    protected

    ## Error pages

    def page_not_found
      if @page = Chemistry::Page.published_with_path("/404")
        render layout: chemistry_layout
      else
        render template: "chemistry/pages/not_found", layout: chemistry_layout
      end
    end


    ## Permitted parameters
    #
    def page_params
      if params[:page].present?
        params.require(:page).permit(
          :title,
          :private,
          :parent_id,
          :page_collection_id,
          :page_category_id,
          :summary,
          :passworded,
          :password,
          :featured,
          :featured_at,
          :apparently_published_at,
          terms: []
        )
      else
        {}
      end
    end

    def search_params
      params.permit(:page_collection, :page_category, :month, :year, :date_from, :date_to, :q, :sort, :order, :show, :page, terms: [], country_codes: [], institution_codes: [], award_type_codes: [], years: [])
    end


    ## Searchable configuration
    #
    def search_class
      Chemistry::Page
    end

    def search_fields
      ['title^5', 'content', 'byline']
    end

    def search_highlights
      {tag: "<strong>"}
    end

    def search_default_sort
      "date"
    end

    # for the public archive page we facet using slug parameters for readability and consistency with urls
    def search_aggregations
      ['page_collection', 'page_category', 'terms']
    end

    def paginated?
      true
    end

    def search_load?
      false
    end

    def get_view
      if %w{config}.include?(params[:view])
        @view = params[:view]
      end
    end
  end
end
