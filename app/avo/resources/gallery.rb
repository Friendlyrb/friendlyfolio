class Avo::Resources::Gallery < Avo::BaseResource
  # self.icon = "tabler/outline/users"
  # self.avatar = {
  #   source: :avatar
  # }
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    # field :avatar, as: :avatar
    field :slug, as: :text
    field :title, as: :text
    field :held_on, as: :date
    field :photographer, as: :text
    field :description, as: :textarea
    field :published_at, as: :date_time
    field :cover_photo_id, as: :number
    field :photos_count, as: :number
    field :sections, as: :has_many
    field :photos, as: :has_many, through: :sections
    field :cover_photo, as: :belongs_to
  end
end
