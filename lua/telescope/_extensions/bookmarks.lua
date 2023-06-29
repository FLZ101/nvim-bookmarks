return require("telescope").register_extension {
  setup = require("bookmarks").telescope.setup,
  exports = {
    bookmarks = require("bookmarks").telescope.run,
    actions = require("bookmarks").telescope.actions
  },
}
