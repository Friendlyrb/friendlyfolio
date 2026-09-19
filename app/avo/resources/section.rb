class Avo::Resources::Section < Avo::BaseResource
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
    field :gallery_id, as: :number
    field :slug, as: :text
    field :title, as: :text
    field :description, as: :textarea
    field :position, as: :number
    field :photos_count, as: :number
    field :gallery, as: :belongs_to
    field :photos, as: :has_many
  end
end
