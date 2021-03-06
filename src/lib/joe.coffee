# Import
util = require('util')
{EventEmitterGrouped} = require('event-emitter-grouped')
{Task, TaskGroup} = require('taskgroup')

# Prepare
isBrowser = window?
isWindows = process?.platform?.indexOf('win') is 0


# =================================
# Test

Test = class extends Task
	@create: (args...) -> new @(args...)
	@isTest: (test) -> return test instanceof Test

	constructor: ->
		super

	setConfig: ->
		super
		me = @

		if before = @config.before
			delete @config.before
			@on 'before', (complete) ->
				before.call(this, me, complete)

		if after = @config.after
			delete @config.after
			@on 'after', (complete) ->
				after.call(this, me, complete)

		@

	run: ->
		if @hasStarted() is false
			@emitSerial 'before', (err) =>
				@emit('error', err)  if err
				super
		else
			super
		@

	complete: ->
		if @isComplete()
			@emitSerial 'after', (err) =>
				@emit('error', err)  if err
				super
		else
			super
		@


# =================================
# Suite

Suite = class extends TaskGroup
	@create: (args...) -> new @(args...)
	@isSuite: (suite) -> return suite instanceof Suite

	constructor: ->
		super
		me = @

		# Shallow Listeners
		@on 'item.add', (item) ->
			if Test.isTest(item)
				item.on 'started', ->
					me.testRunCallback(item)
				item.done (err) ->
					me.testCompleteCallback(item, err)
				item.on 'before', (complete) ->
					me.emitSerial('test.before', item, complete)
				item.on 'after', (complete) ->
					me.emitSerial('test.after', item, complete)

			else if Suite.isSuite(item)
				item.on 'started', ->
					me.suiteRunCallback(item)
				item.done (err) ->
					me.suiteCompleteCallback(item, err)
				item.on 'before', (complete) ->
					me.emitSerial('suite.before', item, complete)
				item.on 'after', (complete) ->
					me.emitSerial('suite.after', item, complete)

		# Nested Listeners
		@on 'item.add', nestedListener = (item) ->
			if Test.isTest(item)
				item.on 'before', (complete) ->
					me.emitSerial('nested.test.before', item, complete)
				item.on 'after', (complete) ->
					me.emitSerial('nested.test.after', item, complete)

			else if Suite.isSuite(item)
				item.on('item.add', nestedListener)
				item.on 'before', (complete) ->
					me.emitSerial('nested.suite.before', item, complete)
				item.on 'after', (complete) ->
					me.emitSerial('nested.suite.after', item, complete)

		# Chain
		@

	setConfig: ->
		super
		me = @

		if before = @config.before
			delete @config.before
			@on 'before', (complete) ->
				before.call(this, me, complete)

		if after = @config.after
			delete @config.after
			@on 'after', (complete) ->
				after.call(this, me, complete)

		@

	run: ->
		if @hasStarted() is false
			@emitSerial 'before', (err) =>
				@emit('error', err)  if err
				super
		else
			super
		@

	complete: ->
		if @isComplete()
			@emitSerial 'after', (err) =>
				@emit('error', err)  if err
				super
		else
			super
		@

	addMethod: (method, config={}) ->
		config.reporting ?= false
		config.name ?= false
		config.args ?= [@suite.bind(@), @test.bind(@)]
		return super(method, config)


	# =================================
	# Callbacks


	suiteRunCallback: (suite) ->
		config = suite.getConfig()

		if config.reporting isnt false
			joePrivate.totalSuites++
			joe.report('startSuite', suite)

	suiteCompleteCallback: (suite, err) ->
		config = suite.getConfig()

		if err
			joePrivate.addErrorLog({suite, err})
			if config.reporting isnt false
				joePrivate.totalFailedSuites++

		else
			if config.reporting isnt false
				joePrivate.totalPassedSuites++

		if config.reporting isnt false
			joe.report('finishSuite', suite, err)

	testRunCallback: (test) ->
		config = test.getConfig()

		if config.reporting isnt false
			joePrivate.totalTests++
			joe.report('startTest', test)

	testCompleteCallback: (test, err) ->
		config = test.getConfig()

		if err
			joePrivate.addErrorLog({test, err})
			if config.reporting isnt false
				joePrivate.totalFailedTests++
		else
			if config.reporting isnt false
				joePrivate.totalPassedTests++

		if config.reporting isnt false
			joe.report('finishTest', test, err)


# =================================
# Methods

Suite::suite = Suite::describe = (args...) ->
	suite = new Suite(args...)
	@addGroup(suite)

Suite::test = Suite::it = (args...) ->
	test = new Test(args...)
	@addTask(test)


# =================================
# Event Emitter Grouped

# Add event emtiter grouped to our classes
for key,value of EventEmitterGrouped::
	Test::[key] = Suite::[key] = value


# =================================
# Private Interface

# Creare out private interface for Joe
# The reason we have a public and private interface for joe is that we do not want tests being able to modify the test results
# As such, the private interface contains properties that must be mutable by the public interface, but not mutable by the bad tests
joePrivate =

	# Global Suite
	# We use a global suite to contain all of the Suite suites and joe.test tests
	globalSuite: null

	# Get Global Suite
	# We have a getter for the global suite to create it when it is actually needed
	getGlobalSuite: ->
		# If it doesn't exist, then create it and name it joe
		unless joePrivate.globalSuite?
			joePrivate.globalSuite = new Suite(
				reporting: false
				name: false
			).run()

		# Return the global suite
		return joePrivate.globalSuite

	# Error Logs
	# We log all the errors that have occured with their suite and test
	# so the reporters can access them
	errorLogs: [] # [{err,suite,test,name}]

	# Add Error Log
	# Logs an error into the errors array, however only if we haven't already logged it
	# log = {err,suite,test,name}
	addErrorLog: (errorLog) ->
		if errorLog.err is joePrivate.errorLogs[joePrivate.errorLogs.length-1]?.err
			# ignore
		else
			joePrivate.errorLogs.push(errorLog)
		return joePrivate

	# Exited?
	# Whether or not joe has already exited, either via error or via finishing everything it is meant to be doing
	# We store this flag, as we do not want to exit multiple times if we have multiple errors or exit signals
	exited: false

	# Reports
	# This is a listing of all the reporters we will be using
	# Reporters are what output the results of our tests/suites to the user (Joe just runs them)
	reporters: []

	# Totals
	# Here are a bunch of totals we use to calculate our progress
	# They are mostly used by reporters, however we do use them to figure out if joe was successful or not
	totalSuites: 0
	totalPassedSuites: 0
	totalFailedSuites: 0
	totalTests: 0
	totalPassedTests: 0
	totalFailedTests: 0

	# Get Reporters
	# Fetches our reporters when we need them, if none are set,
	# then we fetch the reporter specified by the CLI arguments (if running in the CL), or the default reporter for the environment
	getReporters: ->
		# Check if have no reporters
		if joePrivate.reporters.length is 0
			# Prepare
			reporterName = 'console'

			# Cycle through our CLI arguments
			# to see if we can override our reporterName with one specified by the CLI
			for arg in (process?.argv or [])
				# Do we have our --joe-reporter=REPORTER argument?
				argResult = arg.replace(/^--joe-reporter=/,'')
				if argResult isnt arg
					reporterName = argResult
					break

			# Load our default reporter
			try
				joe.addReporter(reporterName)
			catch err
				console.error("""
					Joe could not load the reporter: #{reporterName}
					Perhaps it's not installed? Try install it using:
					    npm install --save-dev joe-reporter-#{reporterName}
					The exact error was:
					""")
				console.error(err.stack or err.message)
				joe.exit(1)
				return

		# Return our reporters
		return joePrivate.reporters


# =================================
# Public Interface

# Create the interface for Joe
joe =
	# Get Totals
	# Fetches all the different types of totals we have collected
	# and determines the incomplete suites and tasks
	# as well as whether or not everything has succeeded correctly (no incomplete, no failures, no errors)
	getTotals: ->
		# Fetch
		{totalSuites,totalPassedSuites,totalFailedSuites,totalTests,totalPassedTests,totalFailedTests,errorLogs} = joePrivate

		# Calculate
		totalIncompleteSuites = totalSuites - totalPassedSuites - totalFailedSuites
		totalIncompleteTests = totalTests - totalPassedTests - totalFailedTests
		totalErrors = errorLogs.length
		success = (totalIncompleteSuites is 0) and (totalFailedSuites is 0) and (totalIncompleteTests is 0) and (totalFailedTests is 0) and (totalErrors is 0)

		# Return
		result = {
			totalSuites,
			totalPassedSuites,
			totalFailedSuites,
			totalIncompleteSuites,
			totalTests,
			totalPassedTests,
			totalFailedTests,
			totalIncompleteTests,
			totalErrors,
			success
		}
		return result

	# Get Errors
	# Returns a cloned array of all the error logs
	getErrorLogs: ->
		return joePrivate.errorLogs.slice()

	# Has Errors
	# Returns false if there were no incomplete, no failures and no errors
	hasErrors: ->
		return joe.getTotals().success is false

	# Has Exited
	# Returns true if we have exited already
	# we do not want to exit multiple times
	hasExited: ->
		return joePrivate.exited is true

	# Has Reportes
	# Do we have any reporters yet?
	hasReporters: ->
		return joePrivate.reporters isnt 0

	# Add Reporter
	# Add a reporter to the list of reporters we will be using
	addReporter: (reporterInstance) ->
		# Load the reporter
		if typeof reporterInstance is 'string'
			Reporter = require("joe-reporter-#{reporterInstance}")
			reporterInstance = new Reporter()

		# Add joe to the reporter
		reporterInstance.joe = joe

		# Add the reporter to the list of reporters we have
		joePrivate.reporters.push(reporterInstance)

		# Chain
		joe

	# Set Reporter
	# Clear all the other reporters we may be using, and just use this one
	setReporter: (reporterInstance) ->
		joePrivate.reporters = []
		joe.addReporter(reporterInstance)  if reporterInstance?
		joe

	# Report
	# Report and event to our reporters
	report: (event, args...) ->
		# Fetch the reporters
		reporters = joePrivate.getReporters()

		# Check we have reporters
		unless reporters.length
			console.error("Joe has no reporters loaded, so cannot log anything...")
			joe.exit(1)
			return joe

		# Cycle through the reporters
		for reporter in reporters
			reporter[event]?.apply(reporter, args)

		# Chain
		joe

	# Exit
	# Exit our process with the specifeid exitCode
	# If no exitCode is set, then we determine it through the hasErrors call
	exit: (exitCode) ->
		# Check
		return  if joe.hasExited()
		joePrivate.exited = true

		# Determine exit code
		unless exitCode?
			exitCode = if joe.hasErrors() then 1 else 0

		# Stop running more tests
		joePrivate.getGlobalSuite().destroy()

		# Report our exit
		joe.report('exit', exitCode)

		# Kill our process with the correct exit code
		process?.exit?(exitCode)

		# Chain
		joe

	# Uncaught Exception
	# Log an uncaughtException and die
	uncaughtException: (err) ->
		# Check
		return  if joe.hasExited()

		# Report
		unless util.isError(err)
			err = new Error(err)
		joePrivate.addErrorLog({name:'uncaughtException', err})
		joe.report('uncaughtException', err)
		joe.exit(1)

		# Chain
		joe

	# Get Item Name
	getItemName: (item,separator) ->
		if separator
			result = item.getNames({separator})
		else
			result = item.getConfig().name
		return result


# =================================
# Setup

if process?
	unless isWindows
		process.on 'SIGINT', ->
			joe.exit()
	process.on 'exit', ->
		joe.exit()
	process.on 'uncaughtException', (err) ->
		joe.uncaughtException(err)

# Bubbled uncaught exceptions
joePrivate.getGlobalSuite().done (err) ->
	joe.uncaughtException(err)  if err

# Interface
# Create our public interface for creating suites and tests
joe.describe = joe.suite = (args...) ->
	globalSuite = joePrivate.getGlobalSuite()
	globalSuite.suite.apply(globalSuite, args)
joe.it = joe.test = (args...) ->
	globalSuite = joePrivate.getGlobalSuite()
	globalSuite.test.apply(globalSuite, args)

# Freeze our public interface from changes
Object.freeze?(joe)  if !isBrowser

# Export
module.exports = joe