#!/bin/bash

url="https://www.asurascans.com/"
version="0.1.0"
cache_dir="$HOME"/.cache/asuradl/
raw_html="$cache_dir"asura-homepg
db_file="$cache_dir"asura-db.json
agent="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:49.0) Gecko/20100101 Firefox/49.0"

# -d is "if file exists and is a dir" - -f for file
if [[ ! -d "$cache_dir" ]]; then
  mkdir -p "$cache_dir"
fi

version_info() {
  printf "%s" "$version"
}

get_latest() {
  # [ -f "$cache_dir"index.html ] && rm "$cache_dir"index.html
  curl -s -A "$agent" "$url" > "$raw_html"
  # cat "$cache_dir"index.html > "$raw_html"
  home_pg=$(cat "$raw_html")
  # rm "$cache_dir"index.html
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
  gum style --border double --foreground 212 "$rd_chapter"
  dl_images "$rd_chapter"
}

download_images() {
  titledir="$(printf "%s" "$1" | cut -d '/' -f4 | sed 's/"//g' | tr -d '[:space:]')"
  mkdir -p "$cache_dir""$titledir"
  gum spin -- wget -P "$cache_dir""$titledir" -q -U "$agent" -nd -r --level=1 -e robots=off -A jpg,jepg -H "$1"
  cd "$cache_dir""$titledir" && ouch compress "$(\ls -v *.jpg)" 
}

dl_images() {
  gum style --foreground 212 'dl_images... mktemp & get images & async py dl'
  tmp_file="$(mktemp -t mytemp-XXXXXX)"
  echo "$tmp_file"
  curl -s -A "$agent" "$1" > "$tmp_file"
  cat "$tmp_file" | pup 'div[class="rdminimal"] p img json{}' | jq '.[].src'| sed 's/"//g' > "$HOME"/src/asura-bash/images.txt
  rm "$tmp_file"
  gum spin -- python3 "$HOME"/src/asura-bash/async-imgdl.py "$HOME"/src/asura-bash/images.txt
}

fp2_json() {
  gum style --foreground 212 'fp2-json parsing front page'
  results_raw_json=$(printf "%s\n" "$home_pg" | pup 'div[class="luf"] json{}')
  # printf "%s" "$results_json" | jq '.[] | [.children[0].href, .children[0].title, "\(.children[1].children[].children[0].href)"]'
  #print JSON of title, link and latest chapter :)
  fp_json=$(printf "%s\n" "$results_raw_json" | jq '.[] | {title: .children[0].title, link: .children[0].href, latest: "\(.children[1].children[0].children[0].href)"}' | jq -s '.')
  printf "%s\n" "$fp_json" > "$db_file"
}

read_data() {
  # tmpfile=$(cat "$db_file")
  cat "$db_file" | jq '.[].title' |\
    fzf \
      --cycle \
      --bind 'o:execute(cat '"$db_file"' | jq ".[{n}].latest")+abort' \
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
  sleep 1
  fzf_main
}

zip_target() {
  for target in "$@"; do
    if [[ -e "$target" ]]; then # does exist
      if [[ -r "$target" ]]; then # is readable
        if [[ -d "$target" ]]; then  # is dir
          archive=${target%/}
          echo "Archiving: $target"
          echo "zip -mTy9 \"$archive.cbz" \"$target"" # -x \"*.DS_Store\" \"*[Tt]humbs.db\"" 
          zip -mTy9 "$archive.cbz" "$target" # -x "*.DS_Store" "*[Tt]humbs.db"
        else
          echo "Not a directory: $target"
        fi
      else
        echo "Not readable: $target "
      fi
    else
      echo "Not found: $target"
    fi
done
}

fzf_main() {
  fzfopt="$(printf "%s\n" "1:Update chapters" "2:Pick manhwa" "3:Exit" | fzf --with-nth 2 --delimiter ":" | cut -d ':' -f1)"
  case "$fzfopt" in
    1)
    update_exit
    ;;
    2)
    main
    ;;
    3)
    exit 0
    ;;
  esac
}

main() {
  link_opt=$(read_data)
  link_opt=$(echo "$link_opt"|sed 's/\"//g'|tr -d '[:space:]')
  read_handler "$link_opt"
}

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
