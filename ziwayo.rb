require 'watir'
require 'open-uri'
require 'nokogiri'
require 'sanitize'
require 'json'
require 'sentimental'
require 'yaml'
require 'date'

oops = 'oops, you seem to be missing arguments'
$html_title = 'Sentiment Analysis for the keyword "WannaCry"'
#$matrix = []
#with_date d w m y

#returns an array of links to investigate
def get_links(location, pages_to_crawl)
  list_of_links =[]
  b = Watir::Browser.new :chrome
  b.goto(location)
  for x in 0...pages_to_crawl
    begin
      for y in 1..10
	link = b.link id: 'title_'+(x*10+y).to_s
	list_of_links << link.href    
      end
      nxt = b.link href: 'javascript:document.nextform.submit();'
      nxt.exists?
      nxt.click
    rescue
      break
    end
  end
  
  
  puts list_of_links.uniq
  
end


def html_happy(str)
  return str.gsub(" ","-")
end

#creates appropriate GET request
def build_search_url(search,date)
  
  #https://www.startpage.com/do/search?cmd=process_search&query=fish&language=english&cat=web&dgf=1&pl=&ff=&t=air
  #url = 'https://www.startpage.com/do/search?query='+search+'&with_date='+date
  
  #url = 'https://www.startpage.com/do/search?cmd=process_search&query='+search+'&language=english&cat=web&dgf=1&pl=&ff=&t=air'
  
  #dgf=1 means you want as many searches as possible
  
  url = 'https://www.startpage.com/do/search?query='+search+'&dgf=1'
  return url
end




def down_html_from_links_open_uri(links, dir_name)
  Dir.mkdir dir_name unless Dir.exist?(dir_name)
  # problem_links are links that we were not able to download using open-uri for whatever reason
  problem_links = []
  
  for i in 0...links.length
    link = links[i]
    begin
    html_file = "<!--"+link+"-->\n" + open(link).read
    File.write(dir_name+'/'+i.to_s+'.html', html_file)
    puts 'downloaded index'+i.to_s
    rescue
      puts "problem with link "+link+" .. will try to download it later using Watir"
      problem_links << [link, (dir_name+'/'+i.to_s+'.html')]
    end
  end
  
  
  #now waitr kicks in
  #b = Watir::Browser.new :chrome, :switches => %w[--ignore-certificate-errors --disable-popup-blocking --disable-translate --proxy-server=myproxy.com:8080]
  
  b = Watir::Browser.new :chrome
  #b.driver.manage.timeouts.implicit_wait = 6
  for i in 0...problem_links.length
    begin
      Timeout::timeout(6) do
	puts "downloading "+problem_links[i][1]
	b.goto(problem_links[i][0])
	html_file = "<!--"+link+"-->\n" + b.html
	File.write(problem_links[i][1], html_file)
      end
    rescue
      puts "not able to download: "+problem_links[i][0]
    end
  end
  
  
  
  
end


def get_p(doc)
  extract = []
  doc.css('script').remove
  doc.css('p').each do |paragraph|
    extract << paragraph.text.gsub("\n",'').gsub(/\[\d+\]/,'')
  end
  return extract
end

def csv_to_array(csv)
  array = []
  File.open(csv).each_line do |line|
    array << line.to_s.gsub("\n","")
  end
  return array
end

def extract_domain(url)
  url = url.gsub('https://','').gsub('http://','')
  url = url[0...url.index('/')]
  url = url.gsub('www.','')
  return url
end
def remove_spaces_downcase(name)
  return name.gsub(' ','').downcase
end

def ai_points(points)
  if points > 0.25
    return 1.1
  elsif points < -0.25
    return 0.9
  else
    return 1
  end
end


def find_word(para, word)
  return para.scan(/[\t\r\ \n\(]#{word}[\-\'\.\ \,\n\)\!\?]/)
end




def save(data, path)
  File.open(path, "w+") do |f|
    f << data.to_json
  end
end


def create_doc(html_dir, list_of_companies)
  array_of_companies = csv_to_array(list_of_companies)
  articles = ''
  results = {}
  index = 0
  
  #create results has in case we are not supplying one via command line
  if  ARGV[4].nil?
    doc_counter = 0
    Dir.foreach(html_dir) do |item|
      next if item == '.' or item == '..'
      doc_counter+=1
      puts "processing document "+doc_counter.to_s
      
      #puts "processing document " + index.to_s
      index=index+1
      item_location = html_dir+'/'+item
      html_file = File.open(item_location)
      link = html_file.read.lines.first.gsub('<!--','').gsub('-->','').gsub("\n",'')
      article_noko = Nokogiri::HTML(open(html_file))
      raw_title = article_noko.css('title')
      if raw_title.size > 1
	title = raw_title[0].text
      else
	title = raw_title.text
      end
      articles << '<a href='+link+'>'+title+'</a><br>'
      paragraphs = get_p(article_noko)    
      for i in 0 ... array_of_companies.size
	company = array_of_companies[i]
	#bias protection
	next if extract_domain(link).include? remove_spaces_downcase(company)
	array_of_references = []
	for para in 0 ... paragraphs.size
	  #if paragraphs[para].scan(/[\t\r\ \n\(]#{company}[\-\'\.\ \,\n\)\!\?]/).count > 0 
	  if find_word(paragraphs[para],company).count > 0 && 
	    #this is where we need to run AI on each paragraph
	    # Create an instance for usage
	    analyzer = Sentimental.new
	    # Load the default sentiment dictionaries
	    analyzer.load_defaults
	    #points = ai_points(analyzer.score paragraphs[para])
	    points = (`python TextBlob.py "#{paragraphs[para].gsub('"', "'")}"`.to_f + 1).round(2)
	    array_of_references << {:paragraph => paragraphs[para], :sentiment => points}
	  end
	end
	#we check that there are less than 4 references of  the company name, in order to filter out biased articles
	if array_of_references.size > 0 && array_of_references.size < 4
	  if results[company].nil?
	    results[company] = {:sa_score => 1,:articles => []}
	  end
	  average_points = 0 
	  array_of_references.each do |i|
	    #average_points = i[:sentiment]
	    average_points = average_points + i[:sentiment]
	  end
	  average_points = average_points / array_of_references.size
	  results[company][:articles] << {:article_title => title, :article_url => link, :average_article_score => average_points.round(2), :paragraphs => array_of_references}
	end	
      end
      #File.write('last_result.hash', results.to_yaml)
      
    end
    
    # Now the results hash is full and we can give scores to each company
    results.each do |company|
      average_company_score = 0.0
      company[1][:articles].each do |article|
	average_company_score = average_company_score + article[:average_article_score]
      end
      results[company[0]][:sa_score] = average_company_score
    end
    
    File.open("last_result.hash", "w"){|to_file| Marshal.dump(results, to_file)}
    File.write("last_articles.html", articles)
  else
    #results = save(data, path)
    results = File.open(ARGV[4], "r"){|from_file| Marshal.load(from_file)}
	#YAML.load_file(ARGV[3])
    articles = File.open("last_articles.html").read
  end
  
  
  #puts results
  
  
  
  #now we can create our html file
  html_file = File.open('template.html').read
  results = sort_results(results)
  all_companies = ""
  pietable = ""
  company_details = ""
  rank = 0
  #fill all varibales that get plugged into our html file
  article_id = 0
  results.each do |company|
    
    rank+=1
    all_companies << company[0] + ', '
    pietable << '["' + company[0] + '",' + company[1][:sa_score].to_s + "],\n"
    
    
    article_html = ''
      
      
    company[1][:articles].each do |article|
      
      
      #puts article
      
      
      para_table = '<table class="table table-bordered">
	<tr>
	  <th>Paragraph</th>
	  <th>Sentiment Score</th>
	</tr>'
      
      
      article[:paragraphs].each do |para|
	
	highlight_company = find_word(para[:paragraph],company[0])[0]
	
	para_table << '<tr>
	  <td>'+para[:paragraph].sub(highlight_company,'<span class="highlight-match">'+highlight_company+'</span>')+'</td>
	  <td>'+para[:sentiment].to_s+'</td>
	</tr>'
	
	
      end
      para_table << '</table>'
      
      
      article_html << '<div class="panel panel-default">
	<div class="panel-heading panel-heading-custom">
	  <h4 class="panel-title pink_blocks">
	    <a data-toggle="collapse" data-parent="#accordion" href="#'+article_id.to_s+'">
	      '+article[:article_title]+' ['+article[:average_article_score].to_s+' Points]
	    </a>
	  </h4>
	</div>
	<div id="'+article_id.to_s+'" class="panel-collapse collapse">
	  <div class="panel-body"><a href='+article[:article_url]+'>view page</a>'+para_table+'</div>
	</div>
      </div>'
      
      article_id+=1
      
    end
    
    
    #table << '</table>'  0733719063 
    
    
    
    company_html = rank.to_s+'. '+company[0]+' - Total score: '+company[1][:sa_score].round(2).to_s

    
    
    company_details << '<div class="panel panel-default">
      <div class="panel-heading">
	<h4 class="panel-title">
	  <a data-toggle="collapse" data-parent="#accordion" href="#'+html_happy(company[0])+'"><b>'+company_html+'</b></a>
	</h4>
      </div>
      <div id="'+html_happy(company[0])+'" class="panel-collapse collapse">
	<div class="panel-body">'+article_html+'</div>
      </div>
    </div>'
  end
  #simple getting rid of trailing commas and carriage returns
  all_companies=all_companies[0...-2]
  pietable=pietable[0...-2]
  
  #fill variables into our html file
  html_file = html_file.sub('ziwayo{pie}',pietable)
  html_file = html_file.sub('ziwayo{all_companies}',array_of_companies.join(", "))
  html_file = html_file.sub('ziwayo{all_articles}',articles)
  html_file = html_file.sub('ziwayo{company_details}',company_details)
  html_file = html_file.gsub('ziwayo{title}',$html_title)
  html_file = html_file.sub('ziwayo{date}',Date.today.strftime)
  
  
  #output
  #puts html_file
  File.write(ARGV[3], html_file)
end


def sort_results(ca)
  return ca.sort_by{ |i| -i[1][:sa_score] }
end
  

def help()
  puts ''
  puts 'HELP DOCUMENT'
  puts 'the options are:'
  puts ' - download_links [your+search+terms] [number of links you want (must be multiple of 10)]'
  puts ' - download_html [list of links] [destination directory]'
  puts ' - create_doc [directory cointing html files to be searched] [csv file containing companie names to search for] [output file name] [OPTIONAL results hash]'
end


if ARGV[0] == '--help'
  help()
  
elsif ARGV[0] == 'download_links'
  if ARGV[1].nil? || ARGV[2].nil?
    puts oops
    help()
  else
    get_links(build_search_url(ARGV[1],''), (Integer(ARGV[2])/10))
    puts 'links downloaded'
  end
elsif ARGV[0] == 'download_html'
  if ARGV[1].nil? || ARGV[2].nil?
    puts oops
    help()
  else
    #links_array = csv_to_array(ARGV[1]).uniq
    #puts links_array.first
    
    
    links_array = csv_to_array(ARGV[1]).uniq
    down_html_from_links_open_uri(links_array, ARGV[2])
  end
elsif ARGV[0] == 'create_doc'
  if ARGV[1].nil? || ARGV[2].nil?
    puts oops
    help()
  else
    
    create_doc(ARGV[1],ARGV[2])
    
  end


else
  puts "you need to provide some arguments"
  help()
end




