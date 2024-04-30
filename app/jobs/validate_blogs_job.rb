class ValidateBlogsJob
  include Sidekiq::Job

  BATCH_SIZE = 10 # Adjust batch size as needed

  def perform(tasks,auth_token)
    @auth_token = auth_token
    tasks.each_slice(BATCH_SIZE) do |batch_tasks|
      blogs = batch_tasks.map { |task| task["blog"] }
      validate_blog(batch_tasks,blogs)
    end
  end

  private

def validate_blog(tasks,blogs)
  tasks.each_with_index do |task, index |
   response =  blog_template(task ,blogs[index])
   if response.start_with?("Yes")
    update_task_statuses([task], "validated")
  end
  end
end
  
  def blog_template(task, blog)

    prompt_template = <<-PROMPT
    "Evaluate the following blog post for validity:


    Criteria for determining validity:
    1. Relevance: Assess whether the content is relevant to the intended audience and aligns with the blog's theme.
    2. Accuracy: Verify the factual correctness of the information presented in the blog post.
    3. Engagement: Evaluate the readability and engagement level of the content to ensure it captivates and retains the audience's interest.
    4. Originality: Determine if the blog offers unique insights or perspectives on the topic, avoiding plagiarism and regurgitated content.
    5. Ethical Considerations: Consider the ethical implications of the content, ensuring it adheres to industry standards and promotes responsible discourse.

    After reviewing the blog post, provide feedback on its overall validity, Most Importantly start with 'Yes' if it is valid or score 70 according to you out of 100, Otherwise .

    Blog Post:
    {blog}"
  PROMPT

    prompt = Langchain::Prompt::PromptTemplate.new(template: prompt_template, input_variables: ["blog"]).format( blog: blog)
    llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_ACCESS_TOKEN"])
    response = llm.chat(messages: [{ role: "user", content: prompt }]).completion
  end

  def update_task_statuses(tasks,status)
    tasks.each_with_index do |task,index|
      begin
        url = Rails.env.production? ? "https://cc.heymira.ai/api/v1/tasks/#{task['id']}" : "http://localhost:3000/api/v1/tasks/#{task['id']}"
        params = {
          project_id: task["project_id"],
          organization_id: task["organization_id"],
          task: {
            status: "validated",
          }
        }
        options = { headers: { "Authorization" => @auth_token }, body: params }
        HTTParty.patch(url, options)
      rescue StandardError => e
        Rails.logger.error("Error updating task status for task #{task['id']}: #{e.message}")
      end
    end
  end
end
