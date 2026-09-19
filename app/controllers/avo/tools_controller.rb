class Avo::ToolsController < Avo::ApplicationController
  def import_photos
    @page_title = "Import photos"
    add_breadcrumb title: "Import photos"

    @galleries = Gallery.includes(:sections).order(:slug)
  end
end
