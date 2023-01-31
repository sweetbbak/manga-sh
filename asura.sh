#!/bin/bash

version_number="0.1.0"
site="https://www.asurascans.com/"

die() {
	printf "\33[2K\r\033[1;31m%s\033[0m\n" "$*" >&2
	exit 1
}

trim_string() {
    # Usage: trim_string "   example   string    "
    : "${1#"${1%%[![:space:]]*}"}"
    : "${_%"${_##*[![:space:]]}"}"
    printf '%s\n' "$_"
}

# checks if dependencies are present
dep_ch() {
	for dep; do
		command -v "$dep" >/dev/null || die "Program \"$dep\" not found. Please install it."
	done
}

# update cached front page after 30 minutes
is_older(){
  lastup=$(stat -c %Y "$HOME"/src/asura-bash/asura-homepg)
  now=$(date +%s)
  age=$((now - lastup))
  if (( age > 1850 )); then
    get_latest
  else
    home_pg=$(cat asura-homepg)
  fi
}

get_ch_list() {
  ch_list=$(curl -s -A "$agent" "$1")
}

get_latest() {
  [ -f index.html ] && rm index.html
  # wget -O - ...prints to stdout
  home_pg="$(wget -q -O index.html -U "$agent" -H "$site")"
  cat index.html > asura-homepg
  home_pg=$(cat asura-homepg)
}

grab_titles() {
  #titles
  # printf "%s" "$home_pg" | pup 'div[class="luf"] h4 text{}'
  # title + href
    printf "%s" "$home_pg" | pup 'div[class="luf"] [class="series"] json{}' | jq '.[].href'
    printf "%s" "$home_pg" | pup 'div[class="luf"] [class="series"] json{}' | jq '.[].title'
  # printf "%s" "$home_pg" | pup 'div[class="uta"] [class="series"] h4 json{} | jq '.[].text''
}

get_fp() {
  # create key pair list of title and link to manwha page (with all chapters, desc, list of ch. etc...)
  titles_links="$(printf "%s" "$home_pg" | pup 'div[class="luf"] [class="series"] json{}' | jq '.[] | "\(.title)" + "*" + "\(.href)"')"
  printf "%s" "$titles_links" > "$db_file" 
  choice_fp="$(printf "%s\n" "$titles_links" | fzf --cycle --with-nth 1 --delimiter '*' | cut -d'*' -f2 | sed 's/"//g')"
  get_ch_list "$choice_fp"
}

iterate_fp() {
  # the first jq[0-49] and the last empty .[0-2] iterate over links (use sed '/null/d' or grep -v 'null' rm null spc)
  # printf "%s" "$home_pg" | pup 'div[class="luf"] json{} | jq ".[0] | .children[0] | .children | .[0] | .children[0] | .href"'
  printf "%s" "$home_pg" | pup 'div[class="luf"] json{}' | jq '.[] | .children[1] | .children | .[0] | .children[].href' | sed /null/d
}

fzf_send() {
  choice=$(printf "%s\n" "$1" | fzf --cycle --with-nth 4 --delimiter '/')
}

agent="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:49.0) Gecko/20100101 Firefox/49.0"
dl_dir="/home/sweet/src/asura-bash/"
download_dir="${dl_dir:-.}"
db_file="/home/sweet/src/asura-bash/asura-db"

opt_view_fp() {
  is_older
  xyz=$(iterate_fp)
  fzf_send "$xyz"
  printf "%s\n" "\n"
  gum style --border double "$choice"
  # download 
}

opt_choose() {
  is_older
  get_fp
  rd_chapter="$(printf "%s\n" "$ch_list" | pup 'div[id="chapterlist"] a[href] json{}' | jq '.[].href' | fzf --cycle --with-nth 4 --delimiter '/' | sed 's/"//g' | tr -d '[:space:]')"
  gum style --border double --foreground 212 "$rd_chapter"
download_chapter "$rd_chapter"
}

download_chapter() {
  titledir="$(printf "%s" "$1" | cut -d '/' -f4 | sed 's/"//g' | tr -d '[:space:]')"
  mkdir -p "$download_dir"/"$titledir" 
  cd "$download_dir"/"$titledir" && wget -U "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:49.0) Gecko/20100101 Firefox/49.0" -nd -r --level=1  -e robots=off -A jpg,jpeg -H "${rd_chapter}"
  ouch compress "$(\ls -1v *.jpg)" temp.zip && mv temp.zip "$titledir".cbz
}

printf "%s\n" ""
gum_opts="$(gum choose "view front page" "choose new" "bookmarked" "exit")"
case "$gum_opts" in
  "view front page") opt_view_fp ;;
  "choose new") opt_choose ;;
  "bookmarked") ;;
  "exit") exit 0;;
esac
