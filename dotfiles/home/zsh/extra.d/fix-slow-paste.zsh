# This speeds up pasting w/ autosuggest
pasteinit() {
  zle autosuggest-disable
}

pastefinish() {
  zle autosuggest-enable
}
zstyle :bracketed-paste-magic paste-init pasteinit
zstyle :bracketed-paste-magic paste-finish pastefinish
