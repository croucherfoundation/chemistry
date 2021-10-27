module Chemistry
  class PageCollectionsController < Chemistry::ApplicationController
    skip_before_action :authenticate_user!, only: [:index, :show, :archive, :latest], raise: false
    load_resource class: Chemistry::PageCollection, find_by: :slug, only: [:show, :archive, :dashboard, :filter]
    load_resource class: Chemistry::PageCollection, except: [:show, :archive, :dashboard, :filter]
    before_action :get_pages, only: [:show, :features, :archive]


    # Public collection home page
    #
    def show
      render layout: chemistry_layout
    end

    def features
      if stale?(etag: @pages, public: true)
        render partial: "chemistry/pages/feature", collection: @pages, layout: false
      end
    end

    # Admin overview page
    #
    def dashboard
      @page_collections = PageCollection.order(title: :asc)
      render layout: chemistry_admin_layout
    end
  
    # Admin latest-updates page
    # nb. public home page is home#home
    #
    def index
      @page_collections = Chemistry::PageCollection.order(title: :asc)
      render layout: chemistry_admin_layout
    end

    # Admin page quick search
    #
    def filter
      @pages = @page_collection.latest_page_search_results
      render partial: "chemistry/page_collections/filtered", layout: false
    end

    # Admin crud
    #
    def edit
      render layout: chemistry_admin_layout
    end
  
    def update
      if @page_collection.update(page_collection_params)
        redirect_to page_collection_home_url(@page_collection.slug)
      else
        render action: :edit
      end
    end

    def new
      render layout: chemistry_admin_layout
    end
  
    def create
      if @page_collection.update(page_collection_params)
        redirect_to root_url
      else
        render action: :new
      end
    end

    # Control block added to (cacheable) public page if user is signed in.
    #
    def controls
      if params[:slug].present? && can?(:edit, Chemistry::PageCollection)
        @page_collection = Chemistry::PageCollection.find_by(slug: params[:slug])
        render layout: false
      else
        head :no_content
      end
    end


    private

    def get_pages
      @p = params[:p] || 1
      @pp = 14
      @pages = Chemistry::Page.search "*", where: {published: true, page_collection: @page_collection.slug}, order: {published_at: :desc}, load: false, per_page: @pp, page: @p
    end

    def page_collection_params
      if params[:page_collection]
        params.require(:page_collection).permit(:title, :short_title, :slug, :introduction, :cobrand, :featured, :private, :eventful)
      else
        {}
      end
    end

  end
end