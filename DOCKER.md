# Ejecutar PetCare con Docker

## Desarrollo local

```powershell
 docker compose up --build
```

Abrir http://localhost:8080

## Detener

```powershell
 docker compose down
```

## Compilar y subir una imagen

```powershell
 docker build -t petcare-web:latest .
 docker save petcare-web:latest -o petcare-web.tar
```

Para un registro de contenedores, sustituye `REGISTRY` por tu usuario/servidor:

```powershell
 docker tag petcare-web:latest REGISTRY/petcare-web:latest
 docker push REGISTRY/petcare-web:latest
```
