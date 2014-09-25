# OAuth daemon
# Copyright (C) 2013 Webshell SAS
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

async = require 'async'
jf = require 'jsonfile'


module.exports = (env) ->
	db = env.DAL.db
	check = env.engine.check
	exit = env.engine.exit
	shared = {}
	shared.events = env.events
	shared.exit = exit
	shared.check = check
	shared.db = db
	shared.db.apps = env.DAL.db_apps
	shared.db.providers = env.DAL.db_providers
	shared.db.states = env.DAL.db_states
	shared.config = env.config
	exp = {}
	shared.plugins = exp

	exp.plugin = {}
	exp.data = shared

	exp.data.hooks = {}



	exp.data.callhook = -> # (name, ..., callback)
		name = Array.prototype.slice.call(arguments)
		args = name.splice(1)
		name = name[0]
		callback = args.splice(-1)
		callback = callback[0]
		return callback() if not exp.data.hooks[name]
		cmds = []
		args[args.length] = null
		for hook in exp.data.hooks[name]
			do (hook) ->
				cmds.push (cb) ->
					args[args.length - 1] = cb
					hook.apply exp.data, args
		async.series cmds, callback

	exp.data.addhook = (name, fn) ->
		exp.data.hooks[name] ?= []
		exp.data.hooks[name].push fn

	exp.load = (plugin_name) ->
		console.log "Loading '" + plugin_name + "'."
		env.config.plugins.push plugin_name
		plugin_data = require(process.cwd() + '/plugins/' + plugin_name + '/plugin.json')
		if plugin_data.main?
			entry_point = '/' + plugin_data.main
		else
			entry_point = ''
		plugin = require process.cwd() + '/plugins/' + plugin_name + entry_point
		exp.plugin[plugin_name] = plugin
		return

	exp.init = (callback) ->
		for plugin in env.config.plugins
			exp.load plugin
		try
			jf.readFile process.cwd() + '/plugins.json', (err, obj) ->
				throw err if err
				if not obj?
					obj = {}
				for pluginname, pluginversion of obj
					exp.load pluginname

				# Checking if auth plugin is present. Else uses default
				if not shared.auth?
					console.log 'Using default auth'
					auth_plugin = require(env.config.root + '/default_plugins/auth/bin')(env)
					exp.plugin['auth'] = auth_plugin

				# Loading front if not overriden
				if not shared.front?
					console.log 'Using default front'
					front_plugin = require env.config.root + '/default_plugins/front/bin'
					exp.plugin['front'] = front_plugin

				# Loading request
				request_plugin = require(env.config.root + '/default_plugins/request/bin')(env)
				exp.plugin['request'] = request_plugin

				# Loading me
				me_plugin = require(env.config.root + '/default_plugins/me/bin')(env)
				exp.plugin['me'] = me_plugin
				callback true
		catch e
			console.log 'An error occured: ' + e.message
			callback true

	exp.list = (callback) ->
		list = []
		jf.readFile process.cwd() + '/plugins.json', (err, obj) ->
			return callback err if err
			if obj?
				for key, value of obj
					list.push key
			return callback null, list

	exp.run = (name, args, callback) ->
		if typeof args == 'function'
			callback = args
			args = []
		args.push null
		calls = []
		for k,plugin of exp.plugin
			if typeof plugin[name] == 'function'
				do (plugin) ->
					calls.push (cb) ->
						args[args.length-1] = cb
						plugin[name].apply shared, args
		async.series calls, ->
			args.pop()
			callback.apply null,arguments
			return
		return

	exp.runSync = (name, args) ->
		for k,plugin of exp.plugin
			if typeof plugin[name] == 'function'
				plugin[name].apply shared, args
		return

	exp