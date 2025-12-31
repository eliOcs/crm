# Pagy configuration
# See https://ddnexus.github.io/pagy/docs/how-to/

require "pagy/extras/overflow"

# Set default items per page
Pagy::DEFAULT[:limit] = 50

# Handle overflow by returning the last page
Pagy::DEFAULT[:overflow] = :last_page
