kubectl exec -n clawmanager-system minio-7959c98cbd-69vj7 -- sh -c '                                                                                 
    mc alias set lc http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null                                                         
    mc mb -p lc/clawmanager-skills                                                                                                                     
    echo hello | mc pipe lc/clawmanager-skills/skills/_probe.txt                                                                                       
    mc cat lc/clawmanager-skills/skills/_probe.txt                                                                                                     
    mc rm  lc/clawmanager-skills/skills/_probe.txt
  '
