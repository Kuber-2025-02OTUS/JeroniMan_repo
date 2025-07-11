# otus-policy.hcl
# Политика для чтения секретов из otus/cred

path "otus/data/cred" {
  capabilities = ["read", "list"]
}

path "otus/metadata/cred" {
  capabilities = ["read", "list"]
}