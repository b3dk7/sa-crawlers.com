import string
from textblob import TextBlob
import sys
 

reload(sys)  
sys.setdefaultencoding('utf8')

#print sys.argv[1]

testimonial = TextBlob(sys.argv[1])
print testimonial.sentiment[0]