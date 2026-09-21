# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Ships with the activestorage gem, so this is a pin rather than a dependency.
pin "@rails/activestorage", to: "activestorage.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Decodes the blurhash the gem stores in blob metadata. 3KB, vendored.
pin "blurhash" # @2.0.5
