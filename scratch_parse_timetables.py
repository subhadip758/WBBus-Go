md_path = r"C:\Users\Subhadip\.gemini\antigravity\brain\763263d8-76c8-479d-a228-3a76215342ea\.system_generated\steps\1388\content.md"

with open(md_path, 'r', encoding='utf-8') as f:
    content = f.read()

import re
# Find all a tags
all_a = re.findall(r'<a\s+[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', content, re.DOTALL)
print("Total links found in bus-timetable index:", len(all_a))

# Count page links or pagination links
pages = re.findall(r'href=["\']([^"\']*/page/\d+[^"\']*)["\']', content)
print("Pagination links:", pages)

# Print first 20 links
for href, text in all_a[:20]:
    clean_text = text.replace('\n', ' ').strip().encode('ascii', 'ignore').decode('ascii')
    print(f"  {href} -> {clean_text[:40]}")
