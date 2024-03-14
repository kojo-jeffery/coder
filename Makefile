## start: Start coder container 
start:
	docker compose -f docker-compose.yml --env-file ./coder.env up -d	

## stop: Stop coder container 
stop:
	docker compose -f docker-compose.yml --env-file ./coder.env down	

## logs: Tail coder container logs 
logs:
	docker compose -f docker-compose.yml --env-file ./coder.env logs -f 

## show: Show coder containers
show:
	docker compose -f docker-compose.yml --env-file ./coder.env ps 

## clean: Clean coder containers and volumes
clean:
	docker system prune -f && docker volume rm coder_coder_data 

## help: Command to view help
help: Makefile
	@echo
	@echo "Choose a command:"
	@echo
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo
