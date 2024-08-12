#!/bin/bash
# SPDX-License-Identifier: MIT

#
# apply_changes.sh
#
# Copyright 2024. Minhyeok Park <pmh_only@pmh.codes>. MIT Licensed.
# You can read the copyright notice here: https://opensource.org/license/mit
#

#
# this script works like following steps:
#
# 1. reads *desired_state* from .yml files
# 2. fetches *current_state* from CloudFlare origin
# 3. calculates difference between two states
# 4. tries to make *current_state* to *desired_state* with CloudFlare Apis
#

# check required arguments ---

ORIGIN_URL=https://api.cloudflare.com/client/v4
ORIGIN_TOKEN=$1
ZONE_ID=$2

if [ ${#ORIGIN_TOKEN} -lt 1 ] || [ ${#ZONE_ID} -lt 1 ] ; then
  echo "Usage: ./migrate_from_origin <Origin_Token(Cloudflare_Token)> <Zone_Id>"
  exit 1
fi

# check pre-requirements ---

check_prerequirement() {
  $1 --version > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "'$1' not found... stop"
    exit 1
  fi
}

check_prerequirement jq
check_prerequirement yq
check_prerequirement awk
check_prerequirement curl
check_prerequirement base64

# read desired state from *.yml file ---

read_desired_state() {
  for file in *.yml; do
    echo "Serialize $file" >&2

    yq -r '
      [
        ."record-type",
        .name,
        .ip // .target // .content // .nameserver,
        .cloudflare // false,
        .comment // ""
      ] | @base64
    ' "$file"
  done
}

desired_state=$(read_desired_state)
desired_state_list=($desired_state)

echo "Found desired_state: ${#desired_state_list[@]} states"

# fetch current state from Cloudflare API ---

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
      jq '
        [
          .result[]
            | select(
              .type == "A" or
              .type == "CNAME" or
              .type == "TXT" or
              .type == "NS")
            | ([
              .type,
              .name,
              .content,
              .proxied // false,
              .comment // ""
              ]| @base64)

              + "|"
              + .id
        ]
        | join(" ")' -r
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

  while [ $count_left -ne 0 ]; do
    local results=($(find_once_records $page))

    if [ $count_left -lt 0 ]; then
      count_left=${results[0]}
    fi

    (( count_left-=${results[1]} ))
    (( page++ ))

    echo ${results[@]:2}
  done
}

current_state=$(find_all_records)
current_state_list=($current_state)

echo "Found current_state: ${#current_state_list[@]} states"

# calculate difference between *desired_state* and *current_state* ---

calculate_added_state() {
  for state in $desired_state; do
    echo $current_state \
      | awk -F'|' '{ print $1 }' RS=" " \
      | grep -w -q $state

    if [ $? -eq 1 ]; then
      echo $state
    fi
  done
}

calculate_deleted_state() {
  for state in $current_state; do
    echo $desired_state \
      | grep -w -q $(echo $state \
      | awk -F'|' '{ print $1 }')

    if [ $? -eq 1 ]; then
      echo $state
    fi
  done
}

added_state=$(calculate_added_state)
added_state_list=($added_state)

deleted_state=$(calculate_deleted_state)
deleted_state_list=($deleted_state)

echo "Calculated added_state: ${#added_state_list[@]} states"
echo "Calculated deleted_state: ${#deleted_state_list[@]} states"

# make changes via Cloudflare APIs ---

for state in $deleted_state; do
  record_id=$(echo $state | awk -F'|' '{ print $2 }')
  echo Delete dns record: $record_id

  curl "$ORIGIN_URL/zones/$ZONE_ID/dns_records/$record_id" \
    -X "DELETE" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ORIGIN_TOKEN"

  echo
done

for state in $added_state; do
  echo Create dns record: $state
  state=$(echo $state | base64 -d)
  
  record_type=$(echo $state | jq ".[0]" -r)
  record_name=$(echo $state | jq ".[1]" -r)
  record_content=$(echo $state | jq ".[2]" -r)
  record_proxied=$(echo $state | jq ".[3]" -r)
  record_comment=$(echo $state | jq ".[4]" -r)

  [ "$record_type" = "A" ] ||
  [ "$record_type" = "CNAME" ]
  
  record_proxiable=$(
    [ $? -eq 0 ] \
      && echo ",\"proxied\": $record_proxied" \
      || echo ""
  )

  record_commentable=$(
    [ ${#record_comment} -gt 0 ] \
      && echo ",\"comment\": \"$record_comment\"" \
      || echo ""
  )

  curl "$ORIGIN_URL/zones/$ZONE_ID/dns_records" \
    -X "POST" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ORIGIN_TOKEN" \
    -d "{
      \"type\": \"$record_type\",
      \"name\": \"$record_name\",
      \"content\": \"$record_content\"
      $record_proxiable
      $record_commentable
    }"
  
  echo
done

echo "Finished!"
