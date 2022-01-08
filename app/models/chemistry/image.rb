require "open-uri"
module Chemistry
  class Image < ApplicationRecord
    include ActiveStorageSupport::SupportForBase64

    belongs_to :user, class_name: Chemistry.config.user_class, foreign_key: Chemistry.config.user_key

    has_one_base64_attached :file

    scope :created_by, -> users {
      users = [users].flatten
      where(user_id: users.map(&:id))
    }

    def sizes
      {
        thumb:    { resize: "96x96" },
        half:     { resize: "560x" },
        full:     { resize: "1120x" },
        hero:     { resize: "1600x900" },
        original: { resize: ""}
      }
    end

    def file_url(size=:full)
      if file.attached?
        file.variant(self.sizes[size]).processed.url
      else
        ""
      end
    end

    def file_data=(data)
      if data
        self.file = { data: data }
      else
        self.file = nil
      end
    end

    def file_name=(name)
      if file.attached?
        file.filename = name
      end
    end

    def file_type=(content_type)
      if file.attached?
        file.content_type = content_type
      end
    end

    def remote_url=(url)
      if url
        self.file = open(url)
      end
    end

    ## serialization

    def title
      read_attribute(:title).presence || file_file_name
    end

    def file_name
      file.filename if file.attached?
    end

    def file_type
      file.content_type if file.attached?
    end

    def file_size
      nil
    end

    def thumb_url
      file_url(:thumb)
    end

    def half_url
      file_url(:half)
    end

    def full_url
      file_url(:full)
    end

    def hero_url
      file_url(:hero)
    end

    def original_url
      file_url(:original)
    end

    ## Elasticsearch indexing
    #
    searchkick searchable: [:title, :file_name],
               word_start: [:title, :file_name]

    def search_data
      {
        title: title,
        file_name: file_name,
        file_type: file_type,
        file_size: file_size,
        created_at: created_at,
        user: user_id,
        urls: {
          original: original_url,
          hero:  hero_url,
          full: full_url,
          half: half_url
        }
      }
    end

  end
end
