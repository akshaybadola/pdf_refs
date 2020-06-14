import json
import requests
from functools import partial
from bs4 import BeautifulSoup

from q_helper import q_helper


# TODO: There should be a cache of entries
def dict_to_bibtex(bib_dict, json_out=False):
    temp = bib_dict.copy()
    if "author" in temp:
        k = "author"
    elif "authors" in temp:
        k = "authors"
    else:
        return None
    if isinstance(temp[k], str):
        temp[k].split(" ")[-1].lower() + temp["year"] +\
            temp["title"].split(" ")[0].lower()
    else:
        key = temp[k][0].split(" ")[-1].lower() + temp["year"] +\
            temp["title"].split(" ")[0].lower()
    bib = "@" + temp.pop("type") + "{" + key + "\n"
    for k, v in temp.items():
        if k in {"author", "authors"}:
            if isinstance(v, list):
                authors = [", ".join([_.split(" ")[-1], " ".join(_.split(" ")[:-1])])
                           for _ in v]
                bib += "  author" + "={" + " and ".join(authors) + "},\n"
            elif isinstance(v, str):
                bib += "  author" + "={" + v + "},\n"
        else:
            bib += "  " + k + "={" + v + "},\n"
    bib = bib[:-2]
    bib += "\n}"
    if json_out:
        return json.dumps(bib)
    else:
        return bib


def arxiv_get(arxiv_id):
    response = requests.get(f"http://export.arxiv.org/api/query?id_list=" + arxiv_id)
    soup = BeautifulSoup(response.content, features="lxml")
    entry = soup.find("entry")
    abstract = entry.find("summary").text
    title = entry.find("title").text
    authors = [a.text for a in entry.find_all("author")]
    date = entry.find("published").text
    bib_dict = {"abstract": abstract.replace("\n", " ").strip(), "title": title,
                "authors": [a.replace("\n", " ").strip() for a in authors], "year": date[:4],
                "url": f"https://arxiv.org/abs/{arxiv_id}", "type": "article"}
    if bib_dict:
        return dict_to_bibtex(bib_dict, True)
    else:
        return json.dumps("ERROR RETRIEVING")


def _arxiv_success(query, response, content):
    soup = BeautifulSoup(response.content, features="lxml")
    entry = soup.find("entry")
    abstract = entry.find("summary").text
    title = entry.find("title").text
    authors = [a.text for a in entry.find_all("author")]
    date = entry.find("published").text
    bib_dict = {"abstract": abstract.replace("\n", " ").strip(), "title": title,
                "authors": [a.replace("\n", " ").strip() for a in authors],
                "year": date[:4],
                "url": f"https://arxiv.org/abs/{query}", "type": "misc"}
    content[query] = dict_to_bibtex(bib_dict)


def _arxiv_no_result(query, response, content):
    content[query] = ["NO_RESULT"]


def _arxiv_error(query, response, content):
    content[query] = ["ERROR"]


def arxiv_fetch(arxiv_id, q, ret_type="json", verbose=False):
    if verbose:
        print(f"Fetching for arxiv_id {arxiv_id}\n")
    if ret_type == "json":
        response = requests.get(f"http://export.arxiv.org/api/query?id_list=" + arxiv_id)
        q.put((arxiv_id, response))
    else:
        q.put((arxiv_id, "INVALID"))


arxiv_helper = partial(q_helper, _arxiv_success, _arxiv_no_result, _arxiv_error)