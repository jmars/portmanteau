fs = require 'fs'
director = require 'director'
{exec} = require 'child_process'

cwd = process.cwd()

dirs = [
	'controllers'
	'models'
	'views'
	'templates'
	'components'
]

router = new director.cli.Router

router.on /new\s([\w]+)/i, (name) ->
	files =
		'component.json': JSON.stringify
			name: name
			dependencies:
				'jmars/sockrpc':'*'
				'jmars/dustjs':'*'
				'visionmedia/page.js':'*'
		'package.json': JSON.stringify
			author: ''
			name: name
			description: ''
			version: '0.0.1'
			dependencies:
				portmanteau: ''
				express: ''
				stylus: ''
				nib: ''
				jade: ''
				'iced-coffee-script': ''
				'dustjs-linkedin':''

	fs.mkdirSync appdir = "#{cwd}/#{name}"
	for dir in dirs then fs.mkdirSync "#{appdir}/#{dir}"
	for file, contents of files then fs.writeFileSync "#{appdir}/#{file}", contents, 'utf8'
	exec "cp -r #{__dirname}/../template/* #{cwd}/#{name}", -> console.log 'created'

router.dispatch 'on', process.argv.slice(2).join ' '