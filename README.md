# gbsw.hs.kr-gitops
gbsw.hs.kr 도메인 등록/관리 gitops 레포지트리

개발 예정. https://github.com/GBSWHS/gbsw.hs.kr-gitops/issues/1 참고

## example yml format
### A record
```yml
record-type: A
comment: Example Site
name: example.gbsw.hs.kr
ip: 123.234.123.234
cloudflare: true # Cloudflare를 통한 DDoS 방어 / HTTPS 지원 (대신 포트가 80/443으로 제한)
```

### CNAME record
```yml
record-type: CNAME
comment: Example Site
name: example.gbsw.hs.kr
target: d1i9bw1f.cloudfront.com
cloudflare: true
```

### TXT record
```yml
record-type: TXT
comment: Some Value
name: hello.gbsw.hs.kr
content: HELLO_WORLD
```

### NS record
```yml
record-type: NS
comment: Some Nameserver
name: pmh.gbsw.hs.kr
nameserver: ns-773.awsdns-32.net
```
