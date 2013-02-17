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
		'component.json': JSON.stringify({
			name: name
			scripts: ['main.js']
			styles: []
			templates: []
			dependencies: {}
		}, null, 2)
		'package.json': JSON.stringify({
			author: ''
			name: name
			description: ''
			version: '0.0.1'
			dependencies:
				portmanteau: 'https://github.com/jmars/portmanteau/tarball/master'
				express: 'latest'
				stylus: 'latest'
				nib: 'latest'
				'iced-coffee-script': 'latest',
				shoe: 'latest',
				ws: 'latest'
			}, null, 2)

	fs.mkdirSync appdir = "#{cwd}/#{name}"
	for dir in dirs then fs.mkdirSync "#{appdir}/#{dir}"
	for file, contents of files then fs.writeFileSync "#{appdir}/#{file}", contents, 'utf8'
	exec "cp -r #{__dirname}/../template/* #{cwd}/#{name}", -> console.log 'created'

router.dispatch 'on', process.argv.slice(2).join ' '