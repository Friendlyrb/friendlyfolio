class Avo::Resources::Photo < Avo::BaseResource
  self.icon = "tabler/outline/photo"
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
    field :section_id, as: :number
    field :position, as: :number
    field :original_filename, as: :text
    field :width, as: :number
    field :height, as: :number
    field :dominant_color, as: :text
    field :source_digest, as: :text
    field :derivatives_ready_at, as: :date_time
    field :image, as: :file
    field :section, as: :belongs_to
  end
end
