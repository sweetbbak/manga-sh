#!/bin/bash

url="https://www.asurascans.com/"
version="0.3.0"
cache_dir="$HOME"/.cache/asuradl/
raw_html="$cache_dir"asura-homepg
db_file="$cache_dir"asura-db.json
thumbnails="$cache_dir"thumbnails
agent="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:49.0) Gecko/20100101 Firefox/49.0"
manga_reader="$(which rmg)"
# manga_reader='nsxiv'
# manga_reader='zathura'

# -d is "if file exists and is a dir" - -f for file
if [[ ! -d "$cache_dir" ]]; then
  mkdir -p "$cache_dir"
fi

version_info() {
  printf "%s" "$version"
}

get_latest() {
  # get the raw front page html
  curl -s -A "$agent" "$url" > "$raw_html"
  home_pg=$(cat "$raw_html")
}

update_frontpage() {
if [[ -f "$raw_html" ]]; then
  get_latest
else
  lastup=$(stat -c %Y "$raw_html")
  now=$(date +%s)
  age=$((now - lastup))
  # if file is over 30 mins old then get an update
  if (( age > 1850 )); then
    printf "%s\n" "updating database..."
    get_latest
  else
    get_latest
    # home_pg=$(cat "$raw_html")
  fi
fi
}

get_ch_list() {
  ch_list=$(curl -s -A "$agent" "$1")
  rd_chapter="$(printf "%s\n" "$ch_list" | pup 'div[id="chapterlist"] a[href] json{}' | jq '.[].href' | fzf --cycle --with-nth 4 --delimiter '/' | sed 's/"//g' | tr -d '[:space:]')" 
  # gum style --border double --foreground 212 "$rd_chapter"
  title="$(printf "%s" "$rd_chapter" | cut -d '/' -f4 | sed 's/"//g' | tr -d '[:space:]')"
  dl_images "$rd_chapter"
}

dl_images() {
  gum style --border thick --border-foreground 212 --underline --foreground 212 --bold "$title"
  tmp_file="$(mktemp -t mytemp-XXXXXX)"
  # echo "$tmp_file"
  curl -s -A "$agent" "$1" > "$tmp_file"
  cat "$tmp_file" | pup 'div[class="rdminimal"] p img json{}' | jq '.[].src'| sed 's/"//g' > "$HOME"/src/asura-bash/images.txt
  rm "$tmp_file"
  gum spin -- python3 "$HOME"/src/asura-bash/async-imgdl.py "$HOME"/src/asura-bash/images.txt
  cd Images || exit
  zip -q tmp.cbz *
  mv tmp.cbz "$HOME/src/asura-bash/${title}.cbz" && cd "$HOME/src/asura-bash" || exit
  [ -d "$HOME/src/asura-bash/Images" ] && rm -rf Images || exit
  "$manga_reader" "${title}".cbz
  # rmg "${title}".cbz
  exit
}

fp2_json() {
  # json-ify our raw html so we can parse it
  results_raw_json=$(printf "%s\n" "$home_pg" | pup 'div[class="luf"] json{}')
  # get images had to split json of images, too far separated from useful info
  img_raw=$(printf "%s\n" "$home_pg"| pup 'div[class="utao styletwo"] json{}')
  # parse json for the images and make a list
  img_json=$(printf "%s\n" "$img_raw" | jq '.[]|.children[].children[0].children[0].children[0] | .src')
  # print JSON of title, link and latest chapter :)
  fp_json=$(printf "%s\n" "$results_raw_json" | jq '.[] | {title: .children[0].title, link: .children[0].href, latest: "\(.children[1].children[0].children[0].href)"}' | jq -s '.')
  # print our main json to a "database" file
  printf "%s\n" "$fp_json" > "$db_file"
  # print our images to a separate json file
  printf "%s\n" "$img_json" > "$thumbnails"
}

read_data() {
  cat "$db_file" | jq '.[].title' |\
    fzf \
      --cycle \
      --bind 'o:execute(cat '"$db_file"' | jq ".[{n}].latest"| xargs firefox)+abort' \
      --bind 'enter:execute(cat '"$db_file"' | jq ".[{n}].link")+abort' \
      --preview='cat '"$db_file"' | jq ".[{n}]"'
}

read_handler() {
  case "$1" in
  *manga*)
    # link to main page - send to show all chapters
    get_ch_list "$@"
    ;;
  *chapter*)
    # send to download chapter
    dl_images "$@"
    ;;
  esac
}

bookmark() {
  ls
}

update_exit() {
  update_frontpage
  fp2_json
  dblines="$(cat "$db_file" | jq ".[].title" | wc -l)"
  gum style --border double --foreground 212 "Updated ${dblines} entries to Asura Scans database"
  # exit 0
  # sleep 1
  fzf_main
}

# main menu. update => udpate frontpage -- main => main -- read-data => send manhwa to fzf -- exit => :)
fzf_main() {
  fzfopt="$(printf "%s\n" "1:Update chapters" "2:Pick manhwa to download" "3:View cache" "4:Exit"| fzf --with-nth 2 --delimiter ":" | cut -d ':' -f1)"
  case "$fzfopt" in
    1)
    update_exit
    ;;
    2)
    main
    ;;
    3)
    read_data
    ;;
    4)
    exit 0
    ;;
  esac
}

# 
main() {
  # capture output from selecting a manhwa from our "database" file
  link_opt=$(read_data)
  # sanitize the option (remove quotations and trim space) send to read_handler
  link_opt=$(echo "$link_opt"|sed 's/\"//g'|tr -d '[:space:]')
  read_handler "$link_opt"
}

# case statements to handle pre-arguments - pass off to main menu
case "$1" in
  -u|--update) 
    update_exit
  ;;
  -v|--version)
    version_info
  ;;
  -b|--bookmark)
  bookmark
  ;;
  *)
  fzf_main
  ;;
  
esac
