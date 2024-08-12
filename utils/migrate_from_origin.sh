ORIGIN_URL=https://api.cloudflare.com/client/v4
ORIGIN_TOKEN=$1
ZONE_ID=$2

check_parameter() {
  if [ ${#ORIGIN_TOKEN} -lt 1 ] || [ ${#ZONE_ID} -lt 1 ] ; then
    echo "Usage: ./migrate_from_origin <Origin_Token(Cloudflare_Token)> <Zone_Id>"
    exit 1
  fi
}

check_prerequirement() {
  $1 --version > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "'$1' not found... stop"
    exit 1
  fi
}

check_prerequirements() {
  check_prerequirement jq
  check_prerequirement curl
  check_prerequirement base64
}

find_once_records() {
  local page=$1
  local per_page=100

  local api_response=$(
    curl "$ORIGIN_URL/zones/$ZONE_ID/dns_records?page=$page&per_page=$per_page" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $ORIGIN_TOKEN" \
      -s
  )

  local parsed_response=$(
    echo "$api_response" | \
      jq "[.result[] | [.type, .name, .content, .proxied, .comment] | @base64] | join(\" \")" -r
  )

  local total_count=$(echo "$api_response" | jq ".result_info.total_count")
  local count=$(echo "$api_response" | jq ".result_info.count")

  local fetched_count=$(($page * $per_page < $total_count ? $page * $per_page : $total_count))

  echo "Request DNS records from Cloudflare - $fetched_count/$total_count" 1>&2
  echo $total_count $count "$parsed_response"
}

find_all_records() {
  local page=1
  local count_left=-1
  local records=""

  while [ $count_left -ne 0 ]; do
    local results=($(find_once_records $page))

    if [ $count_left -lt 0 ]; then
      count_left=${results[0]}
    fi

    (( count_left-=${results[1]} ))
    (( page++ ))

    records+="${results[@]:2} "
  done

  echo $records
}

parse_json_to_yml() {
  local record=$1
  local decoded_record=$(echo $record | base64 -d)

  local record_type=$(echo $decoded_record | jq ".[0]" -r)
  local record_name=$(echo $decoded_record | jq ".[1]" -r)
  local record_content=$(echo $decoded_record | jq ".[2]" -r)
  local record_proxied=$(echo $decoded_record | jq ".[3]" -r)
  local record_comment=$(echo $decoded_record | jq ".[4] | \"''\"" -r)

  local file_name="$record_type-$record_name.yml"

  case $record_type in
    A)
      cat <<EOF > "$file_name"
record-type: $record_type
comment: $record_comment
name: $record_name
ip: $record_content
cloudflare: $record_proxied
EOF
      ;;
    
    
    CNAME)
      cat <<EOF > "$file_name"
record-type: $record_type
comment: $record_comment
name: $record_name
target: $record_content
cloudflare: $record_proxied
EOF
      ;;
    
    TXT)
      cat <<EOF > "$file_name"
record-type: $record_type
comment: $record_comment
name: $record_name
content: $record_content
EOF
      ;;

      
    NS)
      cat <<EOF > "$file_name"
record-type: $record_type
comment: $record_comment
name: $record_name
nameserver: $record_content
EOF
      ;;
  esac
}

migrate_from_origin () {
  records=$(find_all_records)
  
  for record in $records; do
    parse_json_to_yml $record
  done
}

check_parameter
check_prerequirements
migrate_from_origin
