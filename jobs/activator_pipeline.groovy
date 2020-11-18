pipelineJob("activator-pipeline") {
	description()
	keepDependencies(false)
	authenticationToken('secret')
	parameters {
		stringParam("repourl", "", "")
		stringParam("projectid", "", "")
		stringParam("activator_params", "size=100,region=europe-west2", "")
		stringParam("job_unique_id", "", "")
	}
	definition {
		cpsScm {
			scm {
				git {
					remote {
						url '$repourl'
						credentials("gituser")
					}
				}
			}
			scriptPath("Jenkinsfile")
		}
	}
	disabled(false)
}
