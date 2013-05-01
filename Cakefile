exec = require('child_process').exec

task 'build', 'Compile CoffeeScript', ->
	build = exec 'coffee -c index.coffee'

	build.on 'exit', (code) ->
		process.exit code
