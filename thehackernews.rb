require 'watir'
require 'open-uri'
require 'nokogiri'



def get_links(location, pages_to_crawl)
  list_of_links =[]
  b = Watir::Browser.new :chrome
  b.goto(location)
  for x in 0...pages_to_crawl
    
    links = []
    b.as(:class => "url entry-title page-link").each do |li|
      links << li.href
    end
    #list_of_links << links
    puts links
    if x == pages_to_crawl-1
      break
    end
    
    nxt = b.a(:id => "Blog1_blog-pager-older-link")
    nxt.exists?
    nxt.click
    #puts "links on this page is " + links.size
  end
  
  
  #puts list_of_links.uniq
  
  
  
  
end




get_links('https://thehackernews.com', 140)

